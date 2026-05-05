import Foundation

/// Composite `Transcribing` conformer for the streaming option. Pairs
/// a batch `Transcriber` (TDT v2) with a `StreamingTranscriber` (EOU
/// 120M) under one identifier so call sites that only know about
/// `any Transcribing` (`VoiceInputPipeline`, `RecordingPersister`,
/// Library re-transcribe) work unchanged.
///
/// All the `Transcribing` methods delegate to the batch side — the
/// batch transcript is what gets pasted, persisted, and rendered in
/// `Recording.text`. The streaming sibling is reached via the
/// `streaming` property; the pipeline downcasts (`as?
/// DualPipelineTranscriber`) when wiring partials so non-streaming
/// options (v3, JA) skip the streaming setup entirely.
///
/// `Sendable` because both `Transcriber` (actor) and
/// `StreamingTranscriber` (actor) are sendable. The composite stores
/// only let-bindings to actor references — no mutable per-instance
/// state lives on the composite itself.
final class DualPipelineTranscriber: Transcribing, @unchecked Sendable {

    let batch: Transcriber
    let streaming: StreamingTranscriber

    init(batch: Transcriber, streaming: StreamingTranscriber) {
        self.batch = batch
        self.streaming = streaming
    }

    // MARK: - Transcribing conformance — delegates to batch

    func ensureLoaded() async throws {
        // Pre-warm both in parallel; user gets streaming partials as
        // soon as the pipeline starts feeding. Batch is the
        // authoritative source so its failure surfaces; streaming
        // failures degrade silently — pill simply renders without a
        // partial. (Revisit if user feedback suggests we should
        // surface "live preview unavailable.")
        async let batchLoad: Void = batch.ensureLoaded()
        async let streamLoad: Void = ensureStreamingLoadedQuietly()
        _ = try await batchLoad
        _ = await streamLoad
    }

    private func ensureStreamingLoadedQuietly() async {
        do {
            try await streaming.ensureLoaded()
        } catch {
            await ErrorLog.shared.error(
                component: "DualPipelineTranscriber",
                message: "Streaming engine load failed (degrading to batch-only)",
                context: ["error": ErrorLog.redactedAppleError(error)]
            )
        }
    }

    func transcribe(_ samples: [Float]) async throws -> TranscriptionResult {
        try await batch.transcribe(samples)
    }

    func transcribeFile(_ url: URL) async throws -> TranscriptionResult {
        try await batch.transcribeFile(url)
    }

    var isReady: Bool {
        get async { await batch.isReady }
    }
}
