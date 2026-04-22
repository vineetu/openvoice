import SwiftUI

/// Tiny one-line acknowledgment surfaced on the About pane when the user
/// has clicked a donate link (state transitions to `.donated(Date())`).
///
/// Per spec §6.7, this is "small, quiet, one-time" — not a celebration,
/// not a call to re-donate. The date is formatted in the user's current
/// locale with `.long` style (e.g. "April 21, 2026").
struct DonationAcknowledgment: View {
    let date: Date

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11))
                .foregroundStyle(.pink)
            Text("Thanks for donating on \(Self.formatter.string(from: date))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
