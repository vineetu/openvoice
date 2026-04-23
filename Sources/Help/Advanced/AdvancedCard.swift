import SwiftUI

/// A single card inside an `AdvancedSectionView` (spec v1 §6).
///
/// Compact: title + monospaced badge + 2-line body. On tap the card expands
/// in-place to reveal an `expansionProse` block. The expansion animation,
/// card corner radius, and border stroke are sourced from `HelpSharedStyle`
/// so the Advanced grid reads visually consistent with Basics sub-row
/// detail panels.
///
/// Expansion is driven externally by `isExpanded` (a binding) so the parent
/// can orchestrate:
///   * click-to-toggle on the local card (the common case),
///   * single-click expansion when the navigator deep-links to a slug.
///
/// When `isHighlighted` is true, an accent-tinted border pulses on the card
/// — fired by `HelpNavigator` after a two-phase deep-link (expand → scroll
/// → highlight) and auto-cleared after ~1.5s.
struct AdvancedCard: View {
    let card: AdvancedCardData
    @Binding var isExpanded: Bool
    var isHighlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title + badge row.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                badge
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }

            // 2-line body.
            Text(card.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Expansion prose.
            if isExpanded {
                Divider().opacity(0.5).padding(.top, 2)
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
