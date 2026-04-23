import Foundation
import SwiftUI

/// Protocol adopted by every searchable Help surface (Hero, SubRow,
/// AdvancedCardData, TroubleshootingCardData). Lets `HelpSearchState`
/// filter across the three tabs without the three tab views having to
/// import each other's concrete structs.
///
/// Phase 1A owns Hero + SubRow and conforms them here. Phase 1B owns
/// AdvancedCardData + TroubleshootingCardData and conforms them here.
/// Everything in the Help layer that is filterable by the top search
/// bar should adopt this protocol.
///
/// `searchableText` is a flattened view of every text field the user
/// might plausibly match against — title, subtitle, body, detail prose,
/// badge/chip labels, inline tip text, warning copy. Concrete conforming
/// types decide what to include; the search uses case-insensitive
/// substring match (`localizedCaseInsensitiveContains`) over the merged
/// string.
///
/// `slug` lets the search surface link back to the Feature catalog —
/// useful when a sub-row match needs to force its parent hero visible
/// (redesign spec §8: "Sub-row matches expand their hero automatically
/// so the user sees the row in context").
public protocol HelpSearchable {
    /// The canonical slug registered in `Feature.all`. Used to correlate
    /// matches with navigator state and to find a sub-row's parent hero.
    var slug: String { get }

    /// All user-facing text fields on this surface, flattened into one
    /// array. `HelpSearchState` concatenates them with spaces and does
    /// case-insensitive substring match — no tokenization, no fuzzy.
    var searchableText: [String] { get }
}

/// Central search state for the Help tab. Wired into the top `HelpSearchField`
/// and consumed by every tab view's filtering logic.
///
/// * `query` — the raw typed text. Empty = browse mode, non-empty = filter mode.
/// * `isSearching` — `true` when `query` has any non-whitespace content.
/// * `matches(_:)` — generic over any `HelpSearchable`. Case-insensitive
///   substring match across the merged `searchableText`. Use from each tab view
///   to decide whether a surface is visible.
/// * `frozenPhase` — animation phase captured at the moment search began.
///   `HelpBasicsView`'s `TimelineView` reads `isSearching` to freeze its hero
///   illustrations at a resolved keyframe — Phase 1A consumes this.
///
/// No-op when not searching; iterating over the catalog returns the full
/// list when `isSearching == false`. Filtering is a *view* of the data,
/// never a destructive edit (redesign spec §8).
@MainActor
@Observable
public final class HelpSearchState {
    /// Raw query string bound to `HelpSearchField`.
    public var query: String = ""

    /// Phase captured by `HelpBasicsView` at the moment search started —
    /// used to freeze hero illustrations at a fixed keyframe while the
    /// user is scanning. `nil` when not searching.
    public var frozenPhase: Double?

    public init() {}

    /// `true` when the user has typed anything non-whitespace.
    public var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Normalized query — lowercased, trimmed. Empty string when not searching.
    public var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Matching

    /// Generic substring match across every text field on a searchable
    /// surface. Case-insensitive, diacritic-insensitive via
    /// `localizedStandardContains`. Empty query matches everything.
    public func matches<T: HelpSearchable>(_ surface: T) -> Bool {
        guard isSearching else { return true }
        let query = normalizedQuery
        for field in surface.searchableText where !field.isEmpty {
            if field.localizedStandardContains(query) {
                return true
            }
        }
        return false
    }

    /// Convenience: returns a filtered array of surfaces in their
    /// original order. Plain-search semantic — no ranking, no
    /// highlighting.
    public func filtered<T: HelpSearchable>(_ surfaces: [T]) -> [T] {
        guard isSearching else { return surfaces }
        return surfaces.filter { matches($0) }
    }

    // MARK: - Sub-row → hero expansion

    /// Decide whether a hero should be visible given its sub-rows. Per
    /// spec §8: if ANY sub-row matches the query, the hero surfaces too
    /// so the user sees the match in context — even if the hero's own
    /// text fields don't match.
    ///
    /// Phase 1A calls this with the hero and the collection of its
    /// sub-rows. Returns `true` whenever the hero itself matches OR any
    /// sub-row matches.
    public func shouldShowHero<H: HelpSearchable, R: HelpSearchable>(
        _ hero: H,
        subRows: [R]
    ) -> Bool {
        guard isSearching else { return true }
        if matches(hero) { return true }
        return subRows.contains(where: { matches($0) })
    }

    // MARK: - Animation pause hook

    /// Called by `HelpBasicsView` when the user starts typing — captures
    /// the current animation phase so illustrations freeze at a stable
    /// keyframe. Resuming (search cleared) restores the live timeline.
    public func beginSearch(capturingPhase phase: Double) {
        if frozenPhase == nil {
            frozenPhase = phase
        }
    }

    /// Called when `query` clears — resume live animations.
    public func endSearchIfNeeded() {
        if !isSearching {
            frozenPhase = nil
        }
    }
}

// Phase 1A conforms `Hero` and `SubRow` to `HelpSearchable` in
// `Sources/Help/Basics/BasicsContent.swift`.
// Phase 1B conforms `AdvancedCardData` in
// `Sources/Help/Advanced/AdvancedContent.swift` and
// `TroubleshootingCardData` in
// `Sources/Help/Troubleshooting/TroubleshootingContent.swift`.
// Each conformance publishes `slug: String` + `searchableText: [String]`.
// This file doesn't re-declare the conformances — Swift would reject
// the redundancy — but the protocol they conform to lives here so a
// future data struct has a single place to adopt.
