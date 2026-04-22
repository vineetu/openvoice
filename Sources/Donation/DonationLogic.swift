import Foundation

/// Pure decision function for whether the Home-pane donation card should
/// render right now. Kept as a free function (no dependencies, no
/// side-effects, fully deterministic given its arguments) so the rules
/// from `docs/research/donation-reminder.md` §6 are trivially auditable
/// and testable in isolation.
///
/// Rules, in precedence order:
///
///   1. If `reminderEnabled == false`, never show the card.
///   2. `.dismissedForever` and `.donated(_)` are terminal — never show.
///   3. First fire: `state == .unseen` AND `count >= 100` AND at least
///      7 days have elapsed since install. The 7-day grace exists because
///      asking a first-week user who hasn't decided if they're keeping
///      Jot is the Wikipedia-banner anti-pattern.
///   4. Second (and final) fire: `.dismissedSoft(date)` AND `count >= 500`
///      AND at least 90 days have elapsed since the soft-dismiss.
///   5. After two fires (or any terminal state), never ask again — the
///      terminal-state check in rule 2 enforces this.
///
/// `now` is injected so tests can fix a clock without touching `Date()`.
func shouldShowDonationCard(
    state: DonationState,
    count: Int,
    firstLaunchDate: Date,
    reminderEnabled: Bool,
    now: Date
) -> Bool {
    guard reminderEnabled else { return false }

    switch state {
    case .dismissedForever, .donated:
        return false

    case .unseen:
        return count >= 100 && daysBetween(firstLaunchDate, now) >= 7

    case .dismissedSoft(let dismissedAt):
        return count >= 500 && daysBetween(dismissedAt, now) >= 90
    }
}

/// Whole-day delta between two instants, using the user's current
/// calendar. Uses `.day` components on `startOfDay` anchors so DST
/// transitions don't yield 6-day or 8-day weeks when the real gap is
/// seven days.
private func daysBetween(_ earlier: Date, _ later: Date) -> Int {
    let calendar = Calendar.current
    let a = calendar.startOfDay(for: earlier)
    let b = calendar.startOfDay(for: later)
    return calendar.dateComponents([.day], from: a, to: b).day ?? 0
}
