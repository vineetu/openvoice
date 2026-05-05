import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation

/// Actor wrapping FluidAudio's `StreamingEouAsrManager` (Parakeet EOU
/// 120M, 160 ms chunks). Drives a single `AsyncStream<[Float]>` whose
/// consumer Task awaits `ensureLoaded()` lazily, then calls
/// `process(audioBuffer:)` strictly in mic order. Partials arrive via
/// the manager's `setPartialCallback`.
///
/// Lazy-load architecture: `start(...)` returns immediately after
/// creating the per-session continuation and spawning the consumer
/// task. The consumer awaits `ensureLoaded()` *itself* — meanwhile the
/// audio sink can yield chunks into the unbounded AsyncStream, where
/// they accumulate until the model is warm. Once loaded, the consumer
/// drains the buffered chunks in order. Net effect: even the first
/// recording after app launch shows a live preview (the first partial
/// just arrives a few seconds later than steady-state). Audio is
/// never dropped, never reordered.
///
/// Two ordering invariants matter:
///
/// 1. The audio writer queue (CoreAudio AUHAL serial queue) is the
///    upstream choke-point — every converted chunk arrives in mic order.
/// 2. Continuing in that order through the streaming engine requires a
///    serial sink. Per-chunk `Task { await actor.feed(...) }` does NOT
///    preserve order: tasks awaiting actor entry can land in any order.
///    Yielding to an AsyncStream and consuming with a single Task does.
///
/// We pin `computeUnits = .cpuAndNeuralEngine` so the EOU model loads
/// on ANE rather than spilling to the GPU on first prediction (which
/// can cost many seconds of cold-load latency on macOS).
final actor StreamingTranscriber {

    /// Underlying FluidAudio manager. Single instance across sessions —
    /// `reset()` between sessions wipes streaming caches without
    /// re-loading the CoreML model.
    private var manager: StreamingEouAsrManager?

    /// Where to load the CoreML bundle from. Resolved once at
    /// `ensureLoaded()` time from the shared `ModelCache`.
    private let bundleDirectory: URL

    /// Active session id, captured into the partial-callback closure
    /// each session. The callback closure validates against this when
    /// firing so a late callback from a torn-down session can't
    /// publish into a new generation.
    /// TODO(streaming-cleanup): codex flagged this still doesn't
    /// validate `activeGeneration` from inside the actor. Today the
    /// callback closure captures `generation` at session start so
    /// sessions naturally route to their own publish; revisit if a
    /// real cross-session leak is observed. (defensive item #5)
    private var activeGeneration: UInt64?

    /// Holds the per-session AsyncStream continuation behind a lock so
    /// the synchronous nonisolated `enqueue(samples:)` (called from the
    /// audio writer queue) can yield without crossing the actor
    /// boundary.
    private let continuationBox = ContinuationBox()

    /// Single Task draining the AsyncStream. Created in `start(...)`,
    /// awaited (with a bounded wait) in `finish()`, abandoned in
    /// `cancel()` so a slow in-flight `process(audioBuffer:)` can't
    /// stall stop / cancel responsiveness.
    /// TODO(streaming-cleanup): `start()` overwrites this without
    /// draining a prior task. Pipeline phase gating prevents that
    /// today, but assert/cancel-prior would be cheap. (defensive item #6)
    private var consumerTask: Task<Void, Never>?

    init(bundleDirectory: URL) {
        self.bundleDirectory = bundleDirectory
    }

    /// True once the FluidAudio manager has loaded its model and is
    /// ready to consume audio chunks. With the lazy-load architecture
    /// this is informational only — `start(...)` no longer gates on
    /// it; the consumer task awaits the load internally.
    var isReady: Bool { manager != nil }

    /// Idempotent loader. Pins `computeUnits = .cpuAndNeuralEngine` to
    /// avoid the GPU cold-load penalty observed with the default
    /// `.all`. Surfaces SDK errors as plain `Error`.
    /// TODO(streaming-cleanup): not coalesced — two concurrent callers
    /// can both pass `manager == nil` and load twice. Pipeline doesn't
    /// trigger this today (lazy-load means only the consumer task
    /// calls it per session) but a stored `Task<Void, Error>?`
    /// would harden it. (defensive item #2)
    func ensureLoaded() async throws {
        if manager != nil { return }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        let mgr = StreamingEouAsrManager(
            configuration: config,
            chunkSize: .ms160
        )
        try await mgr.loadModels(from: bundleDirectory)
        manager = mgr
    }

    /// Begin a streaming session. Returns immediately after creating
    /// the per-session continuation and spawning the consumer task.
    /// The consumer:
    ///   1. Awaits `ensureLoaded()` — model loads lazily on the first
    ///      session that needs it.
    ///   2. Calls `manager.reset()` and wires the partial callback.
    ///   3. Drains the AsyncStream, calling `process(audioBuffer:)`
    ///      strictly in order.
    ///
    /// Audio yielded via `enqueue(samples:)` between session start
    /// and first-process is buffered in the unbounded AsyncStream and
    /// drained as soon as the model is ready. So the caller can wire
    /// the audio sink and start capture *before* the model is loaded
    /// — no chunks are lost.
    func start(
        generation: UInt64,
        onPartial: @escaping @Sendable (String, UInt64) -> Void
    ) {
        activeGeneration = generation

        // Create the per-session continuation FIRST so any chunks
        // yielded before the consumer task has done its lazy load
        // accumulate in the unbounded AsyncStream rather than being
        // dropped.
        var holder: AsyncStream<[Float]>.Continuation!
        let stream = AsyncStream<[Float]>(bufferingPolicy: .unbounded) { c in
            holder = c
        }
        continuationBox.set(holder)

        // The consumer task does the lazy load + drain. `bundleDirectory`
        // is captured by the actor; we hop back into the actor
        // (`activeManager()`) to read `manager`.
        consumerTask = Task.detached { [weak self] in
            guard let self else { return }
            // 1. Lazy load. Failure → silently skip; pill will just
            // not show partials. Batch is authoritative.
            do {
                try await self.ensureLoaded()
            } catch {
                await ErrorLog.shared.error(
                    component: "StreamingTranscriber",
                    message: "ensureLoaded failed in consumer (skipping partials)",
                    context: ["error": ErrorLog.redactedAppleError(error)]
                )
                return
            }
            guard let mgr = await self.activeManager() else { return }

            // 2. Reset prior session state, wire callback. setPartialCallback
            // is the live partial path (verified in
            // FluidAudio/.../StreamingEouAsrManager.swift:523-527 — fires
            // from inside processChunkAndDecode whenever new tokens decode).
            await mgr.reset()
            await mgr.setPartialCallback { partial in
                onPartial(partial, generation)
            }

            // 3. Drain. Each `[Float]` chunk is wrapped in a fresh
            // AVAudioPCMBuffer here (the buffer object is not Sendable
            // so we don't pass it across the stream).
            // TODO(streaming-cleanup): consider sharing one
            // pre-allocated AVAudioPCMBuffer if alloc churn becomes
            // an issue. (defensive item #3)
            for await samples in stream {
                if Task.isCancelled { break }
                guard !samples.isEmpty,
                      let buffer = Self.makeBuffer(samples)
                else { continue }
                do {
                    _ = try await mgr.process(audioBuffer: buffer)
                } catch {
                    await ErrorLog.shared.error(
                        component: "StreamingTranscriber",
                        message: "process failed",
                        context: ["error": ErrorLog.redactedAppleError(error)]
                    )
                }
            }
        }
    }

    private func activeManager() -> StreamingEouAsrManager? { manager }

    /// Synchronous, nonisolated. Called from the audio capture writer
    /// queue (already FIFO) for each converted 16 kHz mono Float32
    /// chunk. Yields directly into the per-session AsyncStream — the
    /// consumer task drains in order. Order is preserved end-to-end:
    ///   writer queue → continuation.yield → consumer task → process(audioBuffer:)
    nonisolated func enqueue(samples: [Float]) {
        guard !samples.isEmpty else { return }
        continuationBox.yield(samples)
    }

    /// Build a 16 kHz mono Float32 PCM buffer from a chunk. Returns
    /// nil if AVAudioFormat / buffer allocation fails (extremely rare;
    /// drops the chunk silently).
    private static func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
                standardFormatWithSampleRate: 16_000,
                channels: 1
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let dst = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                dst.update(from: base, count: samples.count)
            }
        }
        return buffer
    }

    /// Flush the stream and the streaming engine. Closes the AsyncStream,
    /// then waits for the consumer Task to drain — but only briefly. A
    /// hung `process(audioBuffer:)` (e.g., CoreML stall) cannot block
    /// stop: after the bounded wait we abandon the consumer and
    /// continue. The returned text is discarded by the pipeline; batch
    /// is authoritative.
    func finish() async -> String? {
        continuationBox.finish()
        await drainConsumerWithTimeout(seconds: 2)
        defer {
            activeGeneration = nil
        }
        guard activeGeneration != nil, let manager else { return nil }
        do {
            return try await manager.finish()
        } catch {
            await ErrorLog.shared.error(
                component: "StreamingTranscriber",
                message: "finish failed",
                context: ["error": ErrorLog.redactedAppleError(error)]
            )
            return nil
        }
    }

    /// Abandon the current session. Drops queued audio, signals the
    /// consumer Task to cancel, but does NOT wait for it — a slow
    /// in-flight `process(audioBuffer:)` would otherwise block Esc /
    /// cancel responsiveness for several seconds. The manager state is
    /// reset asynchronously so the next session starts clean.
    func cancel() async {
        continuationBox.finish()
        consumerTask?.cancel()
        consumerTask = nil
        activeGeneration = nil
        if let mgr = manager {
            // Fire-and-forget reset so a fresh session can run without
            // waiting for the abandoned consumer to drain its in-flight
            // process call.
            Task.detached { await mgr.reset() }
        }
    }

    /// Bounded wait for the consumer task to finish. Returns once
    /// either (a) the consumer task completes, or (b) the timeout
    /// elapses, whichever is first. On timeout we cancel the consumer
    /// and abandon — its in-flight `process` will still wind down on
    /// its own, just not blocking us.
    private func drainConsumerWithTimeout(seconds: TimeInterval) async {
        guard let task = consumerTask else { return }
        consumerTask = nil
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await task.value
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            await group.next()
            group.cancelAll()
        }
        if !task.isCancelled {
            // Either drained naturally, or sleep elapsed first; either
            // way cancel the task so a stuck process call doesn't keep
            // running in the background.
            task.cancel()
        }
    }
}

/// Lock-protected wrapper around `AsyncStream.Continuation`. The
/// synchronous nonisolated `enqueue(samples:)` on the actor reaches
/// the continuation through this box without an actor hop, preserving
/// FIFO from the audio writer queue end-to-end.
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<[Float]>.Continuation?

    func set(_ c: AsyncStream<[Float]>.Continuation?) {
        lock.lock()
        let prev = continuation
        continuation = c
        lock.unlock()
        prev?.finish()
    }

    func yield(_ samples: [Float]) {
        lock.lock()
        let c = continuation
        lock.unlock()
        c?.yield(samples)
    }

    func finish() {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.finish()
    }
}
