import SwiftUI

/// A single card inside the Troubleshooting grid (spec v1 §7).
///
/// Shape mirrors `AdvancedCard` for visual consistency: title + monospaced
/// badge + body paragraph, with a small SF Symbol illustration on the left.
/// Click-to-expand reveals longer diagnostic prose (old HelpPane's prose was
/// terse enough to live in the body; longer fixes move into expansion).
///
/// Expansion state is driven by the parent via `isExpanded` so the navigator
/// can deep-link cards open (spec §11, chatbot v4 ShowFeatureTool contract).
/// When `isHighlighted` is true an accent-tinted border pulses — fired by
/// `HelpNavigator` after a two-phase deep-link, auto-cleared after ~1.5s.
struct TroubleshootingCard: View {
    let card: TroubleshootingCardData
    @Binding var isExpanded: Bool
    var isHighlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row — illustration + title + badge + chevron.
            // Fixed-width leading column (24pt) keeps icons aligned across
            // every card in the grid; `.clipped()` is defensive — the
            // `TSIllustration` helpers already constrain to 24pt.
            HStack(alignment: .top, spacing: 10) {
                card.illustration()
                    .frame(width: 24, height: 24)
                    .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(card.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 6)
                        badge
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
            }

            // Body paragraph.
            Text(card.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Expansion prose.
            if isExpanded {
                Divider().opacity(0.5)
                Text(card.expansionProse)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelpSharedStyle.cardBackground())
        .helpHighlightPulse(isHighlighted: isHighlighted)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(HelpSharedStyle.expandAnimation) { isExpanded.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(card.title). \(card.body)")
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
        .accessibilityHint("Double-tap to \(isExpanded ? "collapse" : "expand")")
    }

    private var badge: some View {
        Text(card.badge)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}
