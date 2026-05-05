import Foundation

/// OS-boundary seam for microphone capture. The live conformer is
/// `AudioCapture` (actor-backed `AVAudioEngine` tap → 16 kHz mono Float32
/// samples + on-disk WAV); the harness conformer in
/// `Tests/JotHarness/` plays back fixture `.wav` data without touching
/// CoreAudio.
///
/// The four methods mirror `AudioCapture`'s existing public surface
/// verbatim; this protocol carries no behavior, only the shape that
/// `JotComposition.build` injects and `VoiceInputPipeline` consumes.
///
/// `Sendable` because conformers cross actor isolation domains —
/// `AudioCapture` is itself an actor (implicitly `Sendable`), and
/// `VoiceInputPipeline` is `@MainActor` while reading the seam.
protocol AudioCapturing: Sendable {
    /// Begin a recording session. Throws `AudioCaptureError` on engine
    /// failure / timeout / file-create failure / converter unavailable.
    func start() async throws

    /// Stop the current session and return the captured audio. Throws
    /// `AudioCaptureError.notRunning` if no session is active.
    func stop() async throws -> AudioRecording

    /// Abort the current session and discard the on-disk WAV. Idempotent
    /// — safe to call when no session is active.
    func cancel() async

    /// Hand the seam a publisher to receive ~10 Hz RMS amplitude values
    /// during recording. Pass `nil` to detach.
    func setAmplitudePublisher(_ publisher: AmplitudePublisher?) async

    /// Optional streaming-sink callback fanned out from the writer
    /// queue with each converted 16 kHz mono Float32 chunk. Used by
    /// the streaming-option pipeline to feed partials to FluidAudio's
    /// EOU engine in lockstep with the on-disk WAV write. Live
    /// conformer copies the closure into the writer queue's
    /// `QueueState`; the harness stub is a no-op (default below).
    /// Pass `nil` to detach.
    func setStreamingSink(_ sink: (@Sendable ([Float]) -> Void)?) async

    /// Stream of mid-recording disconnect events for the active session.
    /// Returns an already-finished stream when no session is running so
    /// the caller's `for await` loop terminates cleanly.
    /// See `docs/plans/mic-disconnect-handling.md`.
    func disconnectEvents() async -> AsyncStream<AudioCaptureDisconnectEvent>

    /// Snapshot of why the bound device may have changed during the
    /// just-finished session — used to surface the
    /// "Recorded with system default" notice. `nil` when no session has
    /// run yet or the saved UID resolved cleanly.
    func lastFallbackInfo() async -> AudioCaptureFallbackInfo?
}

/// Default no-op implementations so the test harness `AudioCapturing`
/// conformer keeps building without each test fixture re-stubbing these.
extension AudioCapturing {
    func disconnectEvents() async -> AsyncStream<AudioCaptureDisconnectEvent> {
        let (stream, continuation) = AsyncStream<AudioCaptureDisconnectEvent>.makeStream()
        continuation.finish()
        return stream
    }

    func lastFallbackInfo() async -> AudioCaptureFallbackInfo? { nil }

    /// Default no-op so harness conformers (and any future seam that
    /// doesn't need streaming) keep compiling without re-stubbing.
    /// The live `AudioCapture` overrides this to drive the writer
    /// queue's `streamingSink` field.
    func setStreamingSink(_ sink: (@Sendable ([Float]) -> Void)?) async {}
}
