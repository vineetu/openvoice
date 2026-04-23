import Foundation

/// A single turn in the Ask Jot conversation. The Role enum is the
/// canonical discriminator — user vs. assistant — and drives bubble
/// alignment + tint in `AskJotView`.
///
/// `id` stays stable for the lifetime of the message, so SwiftUI's
/// `ForEach` can animate insertions/updates without diffing on content.
/// Streaming updates mutate `content` in place on the same `id`; the
/// store appends a fresh `.assistant` message once at stream-start and
/// then keeps updating its `content` until the stream completes.
///
/// `isStreaming` lets the view render a caret / italic "(stopped)"
/// suffix on partials without having to cross-reference the store's
/// top-level state.
///
/// `isVoiceOriginated` is reserved for voice input (§8) — teammate 2B
/// wires the real voice pipeline; today this field is always false.
struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String
    var isStreaming: Bool
    var isVoiceOriginated: Bool

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        isStreaming: Bool = false,
        isVoiceOriginated: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.isVoiceOriginated = isVoiceOriginated
    }
}
