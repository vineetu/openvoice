import Foundation

/// Heterogeneous list-item type for Home / Library so dictation
/// `Recording` rows and `RewriteSession` rows can interleave in a
/// single chronological list without forcing the row view to take a
/// concrete model type.
///
/// Critically, `LibraryItem` is **for list rendering only** — it is
/// never pushed onto a `NavigationStack`. The detail-view destinations
/// register against the *wrapped* concrete models (`Recording` /
/// `RewriteSession`) so each detail view's `@Bindable` binding stays
/// concrete; the button-tap site switches on the case and appends the
/// underlying model.
enum LibraryItem: Identifiable {
    case recording(Recording)
    case rewrite(RewriteSession)

    var createdAt: Date {
        switch self {
        case .recording(let r): r.createdAt
        case .rewrite(let s): s.createdAt
        }
    }

    /// Namespace the SwiftUI list identity by kind so a `Recording` and
    /// a `RewriteSession` can never collide in `ForEach` (each model has
    /// its own UUID space, but SwiftUI's `Identifiable` conformance is
    /// per-`LibraryItem` — a same-UUID coincidence between the two
    /// kinds would otherwise create an ambiguous identity).
    var id: String {
        switch self {
        case .recording(let r): "recording-\(r.id.uuidString)"
        case .rewrite(let s): "rewrite-\(s.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .recording(let r): r.title
        case .rewrite(let s): s.title
        }
    }
}
