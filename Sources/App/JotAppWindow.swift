import SwiftUI

/// Root content view for the unified Jot window — the single destination
/// the menu bar's "Open Jot…" item opens (design doc §1).
///
/// Shape:
///   • `NavigationSplitView(sidebar:detail:)`
///   • Sidebar: `AppSidebar` bound to `selection`.
///   • Detail: the pane for the current selection, rendered directly.
///     Each pane owns its own scroll behavior — `Form.grouped` for
///     settings panes, `List` for Home, and `ScrollView` for Help —
///     so the window can be freely resized by the user and the
///     content scrolls within when the window is smaller than its
///     natural size (`.windowResizability(.contentMinSize)` in
///     `JotApp.swift`).
///
/// Deep children (inline "Set up AI →" links, popover "Learn more →"
/// footers) change the selection by calling the
/// `\.setSidebarSelection` environment closure installed here — no
/// ad-hoc window lookups, no notifications-as-state.
struct JotAppWindow: View {
    /// Buffer written by the menu bar controller BEFORE opening the
    /// window on a cold-open. Read once as the initial `@State` value so
    /// the first render already has the correct sidebar selection — this
    /// avoids a race where a `.jotWindowSetSidebarSelection` notification
    /// posted before the SwiftUI scene materialized would be dropped
    /// (the `.onReceive` observer isn't registered yet). The
    /// notification path below remains authoritative for re-selections
    /// of an already-open window.
    @MainActor static var pendingSelection: AppSidebarSelection?

    @State private var selection: AppSidebarSelection
    @State private var navHistory: NavigationHistory

    /// Shared Help navigator. Owned at this root so every pane (Help,
    /// Ask Jot, Settings popovers) sees the same instance — deep-link
    /// state set by one consumer is always visible to the next one.
    @State private var helpNavigator: HelpNavigator

    /// Shared Ask Jot chatbot store. Owned at this root so the
    /// conversation survives sidebar navigation (chatbot spec v5 §4 +
    /// gotcha #6 — correctness-critical).
    @State private var chatStore: HelpChatStore

    /// Shared chatbot voice-input bridge. Owned at this root so the
    /// `recorder.$state` Combine subscription persists across pane
    /// navigation and the mutual-exclusion with global dictation stays
    /// live the whole time the window is up.
    @State private var voiceInput: ChatbotVoiceInput

    @MainActor
    init(pipeline: VoiceInputPipeline, recorder: RecorderController) {
        self.init(
            pipeline: pipeline,
            recorder: recorder,
            navigationHistory: NavigationHistory()
        )
    }

    init(
        pipeline: VoiceInputPipeline,
        recorder: RecorderController,
        navigationHistory: NavigationHistory
    ) {
        let initial = JotAppWindow.pendingSelection ?? .home
        JotAppWindow.pendingSelection = nil
        _selection = State(initialValue: initial)
        _navHistory = State(initialValue: navigationHistory)
        // Build the store tied to the same navigator instance we own
        // above so `ShowFeatureTool` → navigator → HelpPane routing
        // writes/reads the same observable.
        let nav = HelpNavigator()
        _helpNavigator = State(initialValue: nav)
        _chatStore = State(initialValue: HelpChatStore(navigator: nav))
        _voiceInput = State(initialValue: ChatbotVoiceInput(pipeline: pipeline, recorder: recorder))
    }

    var body: some View {
        NavigationSplitView {
            AppSidebar(
                selection: $selection,
                askJotAvailable: !chatStore.isUnavailable
            )
        } detail: {
            detail
                .environment(\.helpNavigator, helpNavigator)
        }
        .environment(\.navigationHistory, navHistory)
        .environment(\.setSidebarSelection) { newValue in
            selection = newValue
        }
        .environment(\.helpNavigator, helpNavigator)
        .onAppear {
            navHistory.bind(selection: $selection)
        }
        .onReceive(NotificationCenter.default.publisher(for: .jotWindowSetSidebarSelection)) { note in
            if let newSelection = note.userInfo?["selection"] as? AppSidebarSelection {
                selection = newSelection
            }
        }
        .onChange(of: selection) { oldValue, newValue in
            guard oldValue != newValue else { return }
            navHistory.pushCurrent(oldValue)
        }
        // Navigator-driven sidebar mutation — sparkle icons, About
        // row, and `ShowFeatureTool` set `navigator.sidebarSelection`
        // and we mirror that into the bound selection. Clear the
        // navigator field after consumption so the same target
        // re-fires cleanly next time.
        .onChange(of: helpNavigator.sidebarSelection) { _, newValue in
            guard let newValue else { return }
            selection = newValue
            helpNavigator.sidebarSelection = nil
        }
    }

    // MARK: - Detail router

    /// Concrete pane for the current selection. The switch is exhaustive so
    /// adding a case to `AppSidebarSelection` is a compiler-enforced TODO here.
    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home:
            HomePane()
        case .askJot:
            AskJotView(store: chatStore, voiceInput: voiceInput)
        case .settings(let sub):
            switch sub {
            case .general:       GeneralPane()
            case .transcription: TranscriptionPane()
            case .vocabulary:    VocabularyPane()
            case .sound:         SoundPane()
            case .ai:            ArticulatePane()
            case .shortcuts:     ShortcutsPane()
            }
        case .help:
            HelpPane()
        case .about:
            AboutPane()
        }
    }
}
