import AppKit
import SwiftUI
import os.log

/// Dismissible "Support Jot" card rendered inline on `HomePane` below the
/// "Recent" row when `shouldShowDonationCard(...)` returns true.
///
/// Copy is verbatim from `docs/research/donation-reminder.md` §3 — two
/// sentences, no embellishment, no guilt framing, no "100% goes to
/// causes" or "personally vetted" language. The only claim the author
/// has asked us to make about where the money goes is *"the every.org
/// fund that supports education"*. Don't pad it.
///
/// Three donate links (Donate $1 / Donate $2 / Other amount) open
/// every.org in the user's default browser and optimistically flip the
/// state to `.donated(Date())` — there's no receipt or webhook, and
/// that's deliberate (see spec §6.6). Two dismiss controls:
///
///   • "Maybe later" → soft-dismiss (90-day cooldown before re-fire).
///   • "Don't ask again" → hard-dismiss (terminal state).
///
/// Card chrome matches the existing Home "Recent recordings" row:
/// `RoundedRectangle(cornerRadius: 8)` with a hairline stroke. No
/// vibrancy material — this card should read as "part of Home", not as
/// a notification or banner.
struct DonationCard: View {
    @ObservedObject private var donationStore = DonationStore.shared
    private let log = Logger(subsystem: "com.jot.Jot", category: "Donation")

    // MARK: - Copy (spec §3, verbatim)

    private let headline = "Jot is free, and stays free."
    private let pitch = "If it's earned a spot in your workflow, consider donating $1 or $2 through the every.org fund that supports education."

    // MARK: - URLs (spec §3)

    private static let donate1URL = URL(string: "https://www.every.org/@vineet.sriram#/donate?amount=1&frequency=ONCE")
    private static let donate2URL = URL(string: "https://www.every.org/@vineet.sriram#/donate?amount=2&frequency=ONCE")
    private static let donateOtherURL = URL(string: "https://www.every.org/@vineet.sriram")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(pitch)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    donate(Self.donate1URL)
                } label: {
                    Text("Donate $1")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    donate(Self.donate2URL)
                } label: {
                    Text("Donate $2")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    donate(Self.donateOtherURL)
                } label: {
                    Text("Other amount")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer(minLength: 8)

                Button("Maybe later") {
                    donationStore.markDismissedSoft()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

                Button("Don't ask again") {
                    donationStore.markDismissedForever()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Actions

    private func donate(_ url: URL?) {
        guard let url else {
            log.error("Donation URL failed to parse — this is a build-time bug")
            return
        }
        NSWorkspace.shared.open(url)
        // Optimistic transition: see spec §6.6. A false-positive is a
        // better UX than silently re-asking an actual donor.
        donationStore.markDonated()
    }
}
