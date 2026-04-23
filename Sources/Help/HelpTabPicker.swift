import SwiftUI

/// Segmented picker for the three Help sub-tabs (Basics / Advanced /
/// Troubleshooting). Lives directly under the search field inside
/// `HelpPane`.
///
/// Implemented as a native SwiftUI `Picker(style: .segmented)` so the
/// control inherits system focus ring, keyboard navigation, and
/// appearance-mode handling without bespoke styling.
struct HelpTabPicker: View {
    @Binding var selection: HelpTab

    var body: some View {
        Picker("Help section", selection: $selection) {
            ForEach(HelpTab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Help section")
    }
}
