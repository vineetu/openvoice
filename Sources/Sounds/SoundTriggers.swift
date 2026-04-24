import Combine
import Foundation

/// Bridges `RecorderController` state transitions and `lastResult` emissions
/// into `SoundPlayer` calls. Owned by `AppDelegate` for the app lifetime.
///
/// State-transition mapping:
///   `.idle → .recording`            → `recordingStart`
///   `.recording → .idle`            → `recordingCancel` (user aborted; no
///                                     transcription ran)
///   `.recording → .transcribing`    → `recordingStop`
///   `anything → .error(_)`          → `error`
///
/// The `transcriptionComplete` chime rides on `$lastResult` — that publisher
/// fires exactly once per successful transcription, which is what we want.
/// Playing it on `.transcribing → .idle` would also double-fire alongside
/// `lastResult` and a user-facing "error → idle" recovery.
///
/// The initial `.idle` value Combine replays on `.sink` is intentionally
/// swallowed (see `previousState`) so the app doesn't chirp on launch.
@MainActor
final class SoundTriggers {
    private let player: SoundPlayer
    private var previousState: RecorderController.State = .idle
    private var previousArticulateState: ArticulateController.ArticulateState = .idle
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        self.init(player: .shared)
    }

    init(player: SoundPlayer) {
        self.player = player
    }

    func start(recorder: RecorderController) {
        recorder.$state
            .sink { [weak self] next in
                self?.handleTransition(to: next)
            }
            .store(in: &cancellables)

        recorder.$lastResult
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.player.play(.transcriptionComplete)
            }
            .store(in: &cancellables)
    }

    /// Subscribe the articulate controller's state machine into the same
    /// chime vocabulary. Articulate Custom mirrors the dictation flow:
    /// `.recording` fires `recordingStart`, `recording → transcribing`
    /// fires `recordingStop`, `.rewriting → .idle` is treated as the
    /// paste-back "done" moment and fires `transcriptionComplete`.
    /// Articulate Fixed skips the `.recording` step entirely, so it
    /// silently passes through capturing → rewriting → idle with only
    /// the terminal `transcriptionComplete` chime on success.
    func start(articulate: ArticulateController) {
        articulate.$state
            .sink { [weak self] next in
                self?.handleArticulateTransition(to: next)
            }
            .store(in: &cancellables)
    }

    private func handleTransition(to next: RecorderController.State) {
        defer { previousState = next }

        switch (previousState, next) {
        case (.idle, .recording), (.error, .recording):
            player.play(.recordingStart)

        case (.recording, .idle):
            // User hit cancel: the transcribing path would have routed through
            // `.transcribing` first.
            player.play(.recordingCancel)

        case (.recording, .transcribing):
            player.play(.recordingStop)

        case (_, .error):
            player.play(.error)

        default:
            break
        }
    }

    private func handleArticulateTransition(
        to next: ArticulateController.ArticulateState
    ) {
        defer { previousArticulateState = next }

        switch (previousArticulateState, next) {
        case (_, .recording):
            // Entering the mic-live phase from capturing (or error recovery).
            // Uses a dedicated chime (pitch-shifted from recordingStart) so
            // Articulate Custom is audibly distinguishable from dictation.
            player.play(.articulateStart)

        case (.recording, .transcribing):
            player.play(.recordingStop)

        case (.recording, .idle):
            // User aborted before transcription kicked in.
            player.play(.recordingCancel)

        case (.rewriting, .idle):
            // LLM finished and paste-back succeeded — the Articulate
            // analogue of dictation's `lastResult` emission.
            player.play(.transcriptionComplete)

        case (_, .error):
            player.play(.error)

        default:
            break
        }
    }
}
