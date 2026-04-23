import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Top-level mode of the Ask Jot chatbot store.
///
/// - `.idle`: input accepts typing, send button enabled when non-empty,
///   no streaming task in flight.
/// - `.streaming`: a `session.streamResponse(...)` is in flight. Send is
///   disabled; Esc cancels the task. The in-flight assistant message's
///   `isStreaming == true` so the bubble can render a caret.
/// - `.error(message)`: last turn failed hard — we surface the message
///   inline on the assistant bubble, but the store is otherwise ready
///   for another turn. `state` flips back to `.idle` on the next send.
/// - `.unavailable(reason)`: Apple Intelligence is not available; the
///   whole pane is greyed and the input bar is disabled. `reason` drives
///   the pane's empty-state copy.
enum ChatState: Equatable {
    case idle
    case streaming
    case error(String)
    case unavailable(UnavailableReason)
}

/// Narrower mirror of `SystemLanguageModel.Availability.UnavailableReason`
/// so UI code can switch exhaustively without importing FoundationModels
/// into every consumer. `HelpChatStore` maps the real availability values
/// into these cases via `UnavailableReason.from(...)`.
enum UnavailableReason: Equatable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    /// OS < 26 or FoundationModels not importable. Shouldn't happen on a
    /// macOS 26.4+ build, but we keep the case so the pane stays sane if
    /// the user somehow lands here on an older OS.
    case osTooOld
    /// Something new Apple added post-26.4 that we don't recognize.
    case other

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    static func from(_ availability: SystemLanguageModel.Availability) -> UnavailableReason? {
        switch availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .other
            }
        @unknown default:
            return .other
        }
    }
    #endif
}
