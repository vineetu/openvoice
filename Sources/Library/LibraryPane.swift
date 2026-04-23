import SwiftUI

/// Legacy wrapper retained only because the source file is still part of the
/// Xcode target. The sidebar no longer routes here; Home now owns the
/// recordings browser.
struct LibraryPane: View {
    var body: some View {
        RecordingsListView()
    }
}
