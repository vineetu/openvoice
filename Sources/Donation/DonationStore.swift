import Combine
import Foundation
import SwiftUI
import os.log

/// Single source of truth for the donation-reminder state machine.
///
/// Backed entirely by `UserDefaults.standard`. The store exists because
/// the donation flow needs four pieces of on-device state:
///
///   • `jot.donation.state`         — JSON-encoded `DonationState`, default `.unseen`.
///   • `jot.donation.recordingCount` — cumulative count of *successfully delivered*
///     transcriptions (incremented by `RecorderController`, never on errors or
///     empty transcripts). Used to gate the first and second card fires.
///   • `jot.install.firstLaunchDate` — `Date` of first read, set-on-first-read if
///     missing. Seeds the "months since install" math for the savings badge
///     and the 7-day grace in the first-fire rule.
///   • `jot.donation.reminderEnabled` — master toggle for BOTH the Home card
///     and the About savings line. Exposed in Settings → General → Reminders.
///
/// All writes are synchronous: the in-memory `@Published` property AND the
/// UserDefaults value update in the same main-actor step, so UI observers
/// and cross-process reads (e.g. a future CLI helper) can't see a stale
/// disk snapshot. No telemetry — these counters never leave the Mac. See
/// `docs/research/donation-reminder.md` §7.5.
@MainActor
final class DonationStore: ObservableObject {
    static let shared = DonationStore()

    // MARK: - UserDefaults keys

    private enum Keys {
        static let state = "jot.donation.state"
        static let recordingCount = "jot.donation.recordingCount"
        static let firstLaunchDate = "jot.install.firstLaunchDate"
        static let reminderEnabled = "jot.donation.reminderEnabled"
    }

    // MARK: - Published state

    @Published var state: DonationState
    @Published var recordingCount: Int
    @Published var firstLaunchDate: Date
    /// Master toggle for Home card + About savings line. SwiftUI binds to
    /// this via `$donationStore.reminderEnabled`; the `reminderToggleSink`
    /// below mirrors changes to UserDefaults so the value survives relaunch.
    @Published var reminderEnabled: Bool

    // MARK: - Internals

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "com.jot.Jot", category: "Donation")
    private var reminderToggleSink: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // 1. Decode `DonationState` if present; fall back to `.unseen`.
        if let data = defaults.data(forKey: Keys.state),
           let decoded = try? JSONDecoder().decode(DonationState.self, from: data) {
            self.state = decoded
        } else {
            self.state = .unseen
        }

        // 2. Recording count — default 0 (UserDefaults returns 0 for an
        //    unset integer key, which is what we want).
        self.recordingCount = defaults.integer(forKey: Keys.recordingCount)

        // 3. First-launch date — set-on-first-read so the savings-badge
        //    clock starts the moment the user ever opens Jot. Any Date we
        //    compute from this is local-only; it never leaves the device.
        if let existing = defaults.object(forKey: Keys.firstLaunchDate) as? Date {
            self.firstLaunchDate = existing
        } else {
            let now = Date()
            self.firstLaunchDate = now
            defaults.set(now, forKey: Keys.firstLaunchDate)
        }

        // 4. Reminder toggle — default true. `.object(forKey:)` returns nil
        //    when the key has never been written, so we distinguish
        //    "unset (default to true)" from "user wrote false".
        if let raw = defaults.object(forKey: Keys.reminderEnabled) as? Bool {
            self.reminderEnabled = raw
        } else {
            self.reminderEnabled = true
        }

        // Mirror toggle changes to UserDefaults. `dropFirst()` skips the
        // sink's initial replay of the current value so we don't write
        // back what we just read. Fires synchronously on the main actor,
        // so the disk snapshot is consistent with what observers see.
        reminderToggleSink = $reminderEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.defaults.set(newValue, forKey: Keys.reminderEnabled)
            }
    }

    // MARK: - Mutations

    /// Increment `recordingCount` by 1 and persist to UserDefaults. Called
    /// by `RecorderController` on the successful-delivery site — NOT on
    /// errors, cancels, or empty transcripts (see spec §6.1). Safe to call
    /// even when `reminderEnabled == false`: the counter is cheap, and the
    /// toggle only gates *display*, not collection. This keeps the savings
    /// badge accurate the moment a user re-enables the toggle.
    func incrementRecordingCount() {
        recordingCount += 1
        defaults.set(recordingCount, forKey: Keys.recordingCount)
    }

    /// Soft-dismiss — "Maybe later." Moves state to `.dismissedSoft(now)`
    /// so the 90-day cooldown in `DonationLogic.shouldShowDonationCard`
    /// can compute re-fire eligibility.
    func markDismissedSoft() {
        writeState(.dismissedSoft(Date()))
        log.info("Donation card soft-dismissed")
    }

    /// Hard-dismiss — "Don't ask again." Permanent unless the user
    /// re-enables `reminderEnabled` in Settings → General, which does
    /// NOT rewind this enum (the toggle gates display; state stays).
    func markDismissedForever() {
        writeState(.dismissedForever)
        log.info("Donation card hard-dismissed")
    }

    /// Optimistically marks the user as a donor on donate-link click.
    /// We get no webhook, and that is intentional per the no-telemetry
    /// rule. A false-positive here (user clicks and bails) is strictly
    /// better UX than silently re-asking an actual donor.
    func markDonated() {
        writeState(.donated(Date()))
        log.info("Donation flow marked as donated")
    }

    /// Explicit state setter used by tests and by any future reset path.
    /// Writes through to UserDefaults synchronously.
    func setState(_ new: DonationState) {
        writeState(new)
    }

    // MARK: - Persistence

    private func writeState(_ new: DonationState) {
        state = new
        do {
            let data = try JSONEncoder().encode(new)
            defaults.set(data, forKey: Keys.state)
        } catch {
            log.error("Failed to encode DonationState: \(String(describing: error))")
        }
    }
}
