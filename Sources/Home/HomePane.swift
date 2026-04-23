import KeyboardShortcuts
import SwiftUI

/// Landing view for the unified Jot window.
///
/// Home now owns the full recordings browser: banner + shortcut glance at the
/// top, followed by the searchable date-grouped list and recording detail
/// navigation previously hosted under a separate sidebar item.
struct HomePane: View {
    /// Donation reminder card state. Observed so dismissal collapses the
    /// card immediately — the card's `markDismissedSoft` /
    /// `markDismissedForever` mutations flip `@Published state`, which
    /// re-evaluates `shouldShowDonationCard(...)` in the body.
    @ObservedObject private var donationStore = DonationStore.shared

    /// Force the glance HStack to re-read the live shortcut whenever the
    /// user rebinds it — `KeyboardShortcuts` itself posts no change
    /// notification we can bind to, so we observe the change via a
    /// shortcut-rebinding listener installed at `onAppear`.

    var body: some View {
        RecordingsListView(navigationTitle: "Home") {
            VStack(alignment: .leading, spacing: 20) {
                BasicsBanner()

                glance
                    .padding(.top, 8)

                if shouldShowDonationCard(
                    state: donationStore.state,
                    count: donationStore.recordingCount,
                    firstLaunchDate: donationStore.firstLaunchDate,
                    reminderEnabled: donationStore.reminderEnabled,
                    now: Date()
                ) {
                    DonationCard()
                        .transition(.opacity)
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Glance

    private var glance: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Text("Press ")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            + Text(shortcutDisplay)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            + Text(" to dictate")
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
    }

    private var shortcutDisplay: String {
        if let s = KeyboardShortcuts.getShortcut(for: .toggleRecording) {
            return s.description
        }
        return "(not set)"
    }
}
