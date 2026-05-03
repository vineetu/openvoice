import Foundation
import SwiftData

/// Persisted record of a single Rewrite run — both the fixed-prompt
/// (`Rewrite`) and voice-instructed (`Rewrite with Voice`) flavors land
/// here. Selection text, instruction transcript, and LLM output are all
/// stored verbatim so the user can revisit them in Home alongside their
/// dictation `Recording` rows. No audio is persisted for either flavor —
/// the voice instruction's WAV is intentionally dropped.
///
/// `flavor` carries the discriminator as a string (`"fixed"` |
/// `"voice"`) rather than an enum to dodge SwiftData enum-migration
/// friction. `modelUsed` is a denormalized human-readable label
/// composed at write time from `LLMProvider.displayName` and
/// `LLMConfiguration.effectiveModel(for:)` — see plan §3 for the
/// composition rule. It's `String?` (nullable) so a future schema
/// migration that adds the field to existing rows lands cleanly with
/// `nil` for legacy rows.
@Model
final class RewriteSession {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    /// `"fixed"` for the fixed-prompt Rewrite flow, `"voice"` for the
    /// voice-instructed Rewrite-with-Voice flow. String-typed (not
    /// enum) for SwiftData migration safety.
    var flavor: String
    var selectionText: String
    var instructionText: String
    var output: String
    /// Human-readable provider/model label (e.g.
    /// `"Apple Intelligence (on-device)"`, `"OpenAI · gpt-5.4-mini"`).
    /// Nullable for forward-compat — see plan §3.
    var modelUsed: String?
    var title: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        flavor: String,
        selectionText: String,
        instructionText: String,
        output: String,
        modelUsed: String?,
        title: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.flavor = flavor
        self.selectionText = selectionText
        self.instructionText = instructionText
        self.output = output
        self.modelUsed = modelUsed
        self.title = title
    }
}

extension RewriteSession {
    /// Best-guess title from a fresh Rewrite output: first 40 chars,
    /// trimmed, or a placeholder if the output is empty. Mirrors
    /// `Recording.defaultTitle(from:)` so both kinds get the same
    /// "what came out" titling treatment.
    static func defaultTitle(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled rewrite" }
        if trimmed.count <= 40 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 40)
        return String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Compact provider label for the row's metadata line — splits the
    /// stored `"<provider> · <model>"` form on `" · "` and returns the
    /// head. Apple Intelligence stores just the provider name (no
    /// trailing dot), so this returns the same string. Returns `nil`
    /// when `modelUsed` itself is `nil` (legacy rows).
    var modelUsedRowLabel: String? {
        guard let modelUsed else { return nil }
        let head = modelUsed.split(separator: " · ", maxSplits: 1, omittingEmptySubsequences: false).first
        return head.map(String.init) ?? modelUsed
    }
}
