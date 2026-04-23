import SwiftUI

// MARK: - Budget overflow visual indicator (DEBUG only)

#if DEBUG
/// Wraps a Text view and paints a 2pt red outline + corner "+N" label when
/// its content exceeds `maxChars`. A visual tripwire so content regressions
/// are impossible to miss during development.
///
/// The check uses `.count` on the raw string — not a layout-aware width —
/// because the budget in redesign §5 is character-based, not pixel-based.
/// Good enough: pixels vary with font scaling; character budgets don't.
struct BudgetOverflowModifier: ViewModifier {
    let maxChars: Int
    let actualChars: Int

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if actualChars > maxChars {
                    Text("+\(actualChars - maxChars)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(3)
                        .background(Color.white.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .offset(x: 4, y: -4)
                }
            }
            .overlay {
                if actualChars > maxChars {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.red, lineWidth: 2)
                }
            }
    }
}

extension View {
    /// Paints a red outline + "+N" tag when `actualChars` exceeds `maxChars`.
    /// No-op in release builds (the modifier is compiled out entirely).
    func budgetCheck(max maxChars: Int, actual actualChars: Int) -> some View {
        modifier(BudgetOverflowModifier(maxChars: maxChars, actualChars: actualChars))
    }
}
#else
extension View {
    /// Release-build shim: compiles the modifier away.
    @inlinable
    func budgetCheck(max maxChars: Int, actual actualChars: Int) -> some View {
        self
    }
}
#endif
