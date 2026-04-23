import AppKit
import SwiftUI

/// Redesigned Help surface — Phase 1 shell.
///
/// Replaces the v1 flat-grid layout with a three-tab hierarchy
/// (Basics / Advanced / Troubleshooting) per the Help redesign spec v1:
///   * Top: shared `HelpSearchField` bound to `HelpSearchState`.
///   * Middle: segmented `HelpTabPicker` driving a local `selectedTab`.
///   * Bottom: one of `HelpBasicsView` / `HelpAdvancedView` /
///     `HelpTroubleshootingView`.
///
/// Deep-link contract:
///   * NEW path — `HelpNavigator.show(feature:)` sets
///     `switchTab` → this pane honors it, then the tab view reads
///     `pendingExpansion` + `highlightedFeatureId` to expand the target
///     row and pulse its border.
///   * LEGACY path — `InfoPopoverButton` still posts the
///     `jot.help.scrollToAnchor` notification. Phase 2C will migrate
///     the anchor strings to the new slug registry. Until then, this
///     pane catches the notification, clears the search filter, and
///     routes to a tab-level fallback (Basics) so the user at least
///     lands on a non-broken Help screen.
///
/// Search filtering itself is performed inside each tab view — they
/// own their data structures and read the shared `HelpSearchState`
/// through the environment.
struct HelpPane: View {
    /// Shared search state — wired to the search field and read by the
    /// three tab views.
    @State private var searchState = HelpSearchState()

    /// Which sub-tab is currently visible. Mutated locally by the
    /// picker and remotely by `HelpNavigator.switchTab`.
    @State private var selectedTab: HelpTab = .basics

    /// Shared Help navigator. Typically injected by `JotAppWindow`; the
    /// environment default is a harmless placeholder so previews and
    /// the setup wizard don't crash.
    @Environment(\.helpNavigator) private var navigator

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    // Switch on the picker state — each tab view is
                    // responsible for its own layout, animation hooks,
                    // and deep-link consumption.
                    //
                    // `HelpBasicsView` reads `@Environment(\.helpSearchState)`
                    // and `@Environment(\.helpNavigator)` directly — no
                    // explicit init parameters needed. `HelpAdvancedView`
                    // and `HelpTroubleshootingView` take `pendingExpansion`
                    // + `onConsumePendingExpansion` as plain values because
                    // their consumption contract is straightforward.
                    tabContent
                        .environment(\.helpSearchState, searchState)
                        .transition(.opacity)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                // Force the enclosing `NSScrollView` to use overlay
                // scrollers regardless of the user's "Show scroll bars"
                // preference. Without this, "Always" users see the
                // content reflow horizontally by ~15pt whenever a tab
                // switch crosses the overflow boundary (e.g. Basics →
                // Troubleshooting), because the legacy scroller eats
                // content width only on the overflowing tab. Overlay
                // scrollers float above content and take no space.
                .background(OverlayScrollerEnforcer())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // If a deep-link was requested before HelpPane mounted
            // (e.g. Ask Jot slug click that also flipped the sidebar),
            // consume the pending state on first appear — .onChange
            // below only fires on value CHANGES, not on initial state
            // when the view first appears in the hierarchy.
            .onAppear {
                guard let targetTab = navigator.switchTab else { return }
                if searchState.isSearching {
                    searchState.query = ""
                    searchState.endSearchIfNeeded()
                }
                selectedTab = targetTab
                if let slug = navigator.pendingExpansion {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(HelpSharedStyle.scrollAnimation) {
                            proxy.scrollTo(slug, anchor: .top)
                        }
                    }
                }
                navigator.clearSwitchTab()
            }
            // NEW deep-link consumption — navigator drives tab switch
            // and the tab views consume `pendingExpansion` themselves.
            .onChange(of: navigator.switchTab) { _, newValue in
                guard let newValue else { return }
                if searchState.isSearching {
                    searchState.query = ""
                    searchState.endSearchIfNeeded()
                }
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedTab = newValue
                }
                // Defer the scroll so the tab view has mounted and
                // consumed `pendingExpansion` before we try to resolve
                // the target slug via `proxy.scrollTo`.
                if let slug = navigator.pendingExpansion {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(HelpSharedStyle.scrollAnimation) {
                            proxy.scrollTo(slug, anchor: .top)
                        }
                    }
                }
                // Consumed — clear so a re-render of the same target
                // doesn't re-fire the pulse.
                navigator.clearSwitchTab()
            }
            // LEGACY deep-link bridge — Settings' `InfoPopoverButton`
            // continues to post `jot.help.scrollToAnchor` with string
            // anchors until Phase 2C migrates them to slugs. We catch
            // the notification, clear the filter, and try to match the
            // anchor against a known slug. Unknown anchors fall back to
            // Basics so the user at least lands on a valid tab.
            .onReceive(
                NotificationCenter.default.publisher(for: InfoPopoverButton.scrollToAnchorNotification)
            ) { note in
                guard let anchor = note.userInfo?["anchor"] as? String else { return }
                if searchState.isSearching {
                    searchState.query = ""
                    searchState.endSearchIfNeeded()
                }
                // If the anchor is a known slug, route through the
                // navigator so the tab view can run the full two-phase
                // deep-link. Otherwise land on Basics silently.
                if let feature = Feature.bySlug(anchor), feature.isDeepLinkable {
                    navigator.show(feature: feature)
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = .basics
                    }
                    // Best-effort scroll using the legacy anchor — tab
                    // views that still pin `.id(anchorString)` on their
                    // cards during the Phase 2C transition will pick
                    // this up; otherwise it's a no-op.
                    DispatchQueue.main.async {
                        withAnimation(HelpSharedStyle.scrollAnimation) {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab routing

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .basics:
            // Phase 1A's `HelpBasicsView` reads `helpSearchState` and
            // `helpNavigator` straight from the environment. We ALSO
            // pass `isSearching` / `searchQuery` through as plain init
            // args because the view's per-hero sub-row filtering keys
            // off those locally-scoped values (its own `activeSearch`
            // computed property) — keeping the env and args in sync
            // means sub-row filtering and the empty-state text agree
            // on when search is active.
            HelpBasicsView(
                isSearching: searchState.isSearching,
                searchQuery: searchState.query
            )
        case .advanced:
            HelpAdvancedView(
                pendingExpansion: pendingExpansionForCurrentTab(.advanced),
                onConsumePendingExpansion: { navigator.clearPendingExpansion() }
            )
        case .troubleshooting:
            HelpTroubleshootingView(
                pendingExpansion: pendingExpansionForCurrentTab(.troubleshooting),
                onConsumePendingExpansion: { navigator.clearPendingExpansion() }
            )
        }
    }

    // MARK: - Navigator wiring

    /// Feed the right `pendingExpansion` value to each tab view — only
    /// the tab currently being targeted by the navigator should see a
    /// non-nil slug. Keeps Advanced from pulsing a Troubleshooting slug
    /// if both views happen to be stale-mounted.
    private func pendingExpansionForCurrentTab(_ tab: HelpTab) -> String? {
        guard selectedTab == tab,
              let slug = navigator.pendingExpansion,
              let feature = Feature.bySlug(slug),
              feature.tab == tab
        else { return nil }
        return slug
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpSearchField(
                text: Binding(
                    get: { searchState.query },
                    set: { newValue in
                        searchState.query = newValue
                        searchState.endSearchIfNeeded()
                    }
                ),
                resultCount: searchState.isSearching ? 1 : Feature.all.count,
                totalCount: Feature.all.count
            )

            HelpTabPicker(selection: $selectedTab)
        }
        .frame(maxWidth: 900, alignment: .leading)
    }

}

// MARK: - Search state environment

/// Placeholder default used by the environment key — replaced by the
/// root view's explicit injection at runtime. Previews and the setup
/// wizard read the default and stay harmless.
@MainActor
private let defaultHelpSearchState = HelpSearchState()

private struct HelpSearchStateKey: @preconcurrency EnvironmentKey {
    @MainActor
    static let defaultValue: HelpSearchState = defaultHelpSearchState
}

extension EnvironmentValues {
    /// Shared search state for the current Help pane instance.
    var helpSearchState: HelpSearchState {
        get { self[HelpSearchStateKey.self] }
        set { self[HelpSearchStateKey.self] = newValue }
    }
}

// MARK: - Overlay scroller enforcement

/// Walks the AppKit hierarchy to find the `NSScrollView` SwiftUI creates
/// for its enclosing `ScrollView`, and forces `scrollerStyle = .overlay`.
/// The effect: scroll indicators float above content instead of eating
/// ~15pt of width in "Show scroll bars: Always" mode — keeping content
/// width identical across tabs that scroll and tabs that don't.
///
/// Installed via `.background(OverlayScrollerEnforcer())` on the VStack
/// inside the ScrollView. The NSView itself is zero-sized and invisible;
/// it exists only so we can hop to its `enclosingScrollView`.
private struct OverlayScrollerEnforcer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        applyOverlay(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyOverlay(to: nsView)
    }

    private func applyOverlay(to view: NSView) {
        // Defer until the view is attached to a window / enclosed scroll
        // view — on first mount the chain isn't wired up synchronously.
        DispatchQueue.main.async { [weak view] in
            view?.enclosingScrollView?.scrollerStyle = .overlay
        }
    }
}
