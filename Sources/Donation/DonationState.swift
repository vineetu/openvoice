import Foundation

/// Lifecycle states for the donation reminder card.
///
/// Persisted as JSON under `jot.donation.state` (see `DonationStore`). The
/// state machine is monotonic: once a user donates or hard-dismisses, the
/// card never appears again for that install. Soft-dismiss carries the
/// dismissal date so the 90-day cooldown in `DonationLogic` can compute
/// re-fire eligibility.
///
/// `.donated` stores the click-through date — we optimistically transition
/// on donate-link click because there is no webhook and the app has no
/// telemetry path to confirm the actual charge on every.org. If a user
/// clicks and bails, re-asking them is a worse UX than a false positive.
enum DonationState: Codable, Equatable {
    case unseen
    case dismissedSoft(Date)
    case dismissedForever
    case donated(Date)
}
