import SwiftUI

/// Compact "Experimental" badge used next to model display names in
/// Settings → Transcription and the Setup Wizard model step. Surfaces
/// the option's experimental status to the user before they commit a
/// download. Visually quiet (orange tint, small caps) so it reads as
/// an advisory marker, not an error.
struct ExperimentalBadge: View {
    var body: some View {
        Text("Experimental")
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.orange.opacity(0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityLabel("Experimental")
    }
}
