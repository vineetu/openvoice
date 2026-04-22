import SwiftUI

/// A single row in the Vocabulary pane: one visible, tappable text field
/// for the term, with a hover-to-reveal delete button.
///
/// The v1.5 "sounds-like" alias field was removed because the plain-text
/// term field was visually indistinguishable from a static label — users
/// clicked "Add Term" and couldn't tell where to type. The `VocabTerm`
/// model still carries an `aliases` array so the file format is stable
/// and the UI can add them back later without a migration.
struct VocabRow: View {
    @Binding var term: VocabTerm
    var focused: FocusState<VocabTerm.ID?>.Binding
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("Term", text: $term.text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .focused(focused, equals: term.id)

            if let warning = warningMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help(warning)
            }

            if isHovered {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete term")
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }

    /// Live inline warning for obvious footguns. Never blocks save —
    /// user is trusted. Two heuristics per research §7:
    ///   • Empty-ish terms (<=2 chars after trim) are too short for the
    ///     CTC rescorer's `minTermLength: 3` and will be silently dropped.
    ///   • Exact matches on very common English words cause false
    ///     replacements. We ship a small hardcoded watchlist rather than
    ///     pull in a 10k-word frequency file for MVP.
    private var warningMessage: String? {
        let t = term.text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return nil }
        if t.count <= 2 {
            return "Too short — terms under 3 characters are skipped to avoid false replacements."
        }
        if Self.commonEnglishWatchlist.contains(t) {
            return "Common English word — may cause false replacements in transcripts that use the word normally."
        }
        return nil
    }

    /// Curated watchlist of common English words that are very likely
    /// to collide with ordinary speech. Deliberately small — a bigger
    /// list belongs in a bundled frequency file in a future phase.
    private static let commonEnglishWatchlist: Set<String> = [
        "the", "and", "for", "that", "with", "this", "from", "have",
        "they", "will", "one", "all", "would", "their", "what", "out",
        "about", "which", "when", "make", "like", "time", "just", "him",
        "know", "take", "into", "year", "your", "good", "some", "could",
        "them", "see", "other", "than", "then", "now", "look", "only",
        "come", "over", "think", "also", "back", "after", "use", "two",
        "how", "our", "work", "first", "well", "way", "even", "new",
        "want", "any", "give", "day", "most", "very", "find", "thing",
        "tell", "say", "get", "made", "part", "get", "yes", "yeah",
    ]
}
