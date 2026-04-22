import SwiftUI

/// One-line "potentially saved" readout surfaced in the About pane below
/// the existing "Donate to charity" button (spec §7.6).
///
/// Format:
///   "You've been using Jot for N months — about $X saved vs $10/mo tools"
///
/// Where `N = floor(monthsSinceInstall)` and `X = N * 10`. Caller is
/// responsible for gating on `N >= 1` so day-one users don't see "$0
/// saved." The adjacent `InfoPopoverButton` carries the honest caveat:
/// "comparable tools charge" — nobody's assuming every Jot user would
/// have paid $10/mo to a competitor; we're just stating the market rate.
///
/// The `reminderEnabled` toggle in Settings → General gates both this
/// badge AND the Home donation card (one switch controls both downstream
/// surfaces), so the caller in `AboutPane` checks that too.
struct SavingsBadge: View {
    /// Whole months elapsed since first launch, as computed by
    /// `DonationStore.firstLaunchDate` + `Calendar.current.dateComponents`.
    let months: Int

    /// Comparable-tools monthly rate (USD). Keep this a constant at the
    /// call site; baking it into a parameter makes the "market rate"
    /// claim explicit and easy to update in one place if competitor
    /// pricing shifts.
    let monthlyRate: Int

    var savings: Int { months * monthlyRate }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("You've been using Jot for \(months) month\(months == 1 ? "" : "s") — about $\(savings) saved vs $\(monthlyRate)/mo tools")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            InfoPopoverButton(
                title: "Savings estimate",
                body: "Calculated from the day you first launched Jot, rounded down to whole months. Comparable dictation tools charge around $\(monthlyRate)/mo; nobody is assuming you would have paid that, just stating the market rate. The count stays on your Mac — nothing is uploaded. Turn this off anytime in Settings → General."
            )
        }
    }
}
