import AppKit
import Combine
import Foundation
import SwiftData
import os.log

/// Owns the `NSStatusItem` (menu-bar extra) and its `NSMenu`. The icon and
/// "Toggle Recording" label are driven by Combine subscriptions to
/// `RecorderController.$state` and `$lastTranscript`.
///
/// This controller is deliberately side-effect free in `init` — creating the
/// `NSStatusItem` happens in `install()` so `AppDelegate` can choose when to
/// actually plant something in the menu bar.
@MainActor
final class JotMenuBarController: NSObject {
    // MARK: - Dependencies

    private let recorder: RecorderController
    private let delivery: DeliveryService
    /// Context for the SwiftData store, used by the "Recent Transcriptions"
    /// submenu to fetch the 10 most recent `Recording` rows on demand.
    private let modelContext: ModelContext
    private let checkForUpdatesAction: () -> Void

    private static let menuBarIconName = NSImage.Name("JotMenuIcon")

    private static func stateIconName(for state: RecorderController.State) -> NSImage.Name {
        switch state {
        case .idle: return NSImage.Name("JotMenuIcon-idle")
        case .recording: return NSImage.Name("JotMenuIcon-recording")
        case .transcribing: return NSImage.Name("JotMenuIcon-transcribing")
        case .transforming: return NSImage.Name("JotMenuIcon-transforming")
        case .error: return NSImage.Name("JotMenuIcon-error")
        }
    }

    // MARK: - UI

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let recentSubmenu = NSMenu()

    private var toggleItem: NSMenuItem?
    private var copyLastItem: NSMenuItem?

    #if JOT_FLAVOR_1
    /// Items currently splicing the flavor_1 PFB Enterprise section into the
    /// root menu. Tracked by reference so a Combine-driven rebuild can remove
    /// exactly those items (separator + section header + state-dependent
    /// rows) without touching the rest of the menu.
    private var flavor1SectionItems: [NSMenuItem] = []
    #endif

    // MARK: - Subscriptions

    private var stateCancellable: AnyCancellable?
    private var transcriptCancellable: AnyCancellable?
    #if JOT_FLAVOR_1
    private var flavor1StateCancellable: AnyCancellable?
    #endif

    private let log = Logger(subsystem: "com.jot.Jot", category: "MenuBar")

    // MARK: - Init

    init(
        recorder: RecorderController,
        delivery: DeliveryService,
        modelContext: ModelContext,
        checkForUpdatesAction: @escaping () -> Void
    ) {
        self.recorder = recorder
        self.delivery = delivery
        self.modelContext = modelContext
        self.checkForUpdatesAction = checkForUpdatesAction
        super.init()
    }

    /// Installs the status item in the system menu bar and wires up Combine
    /// subscriptions. Safe to call exactly once, from
    /// `applicationDidFinishLaunching`.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.icon(for: recorder.state)
        item.button?.image?.isTemplate = true
        item.button?.toolTip = Self.accessibilityDescription(for: recorder.state)
        item.menu = buildMenu()
        statusItem = item

        stateCancellable = recorder.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.applyState(state)
            }

        transcriptCancellable = recorder.$lastTranscript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                self?.copyLastItem?.isEnabled = (transcript?.isEmpty == false)
            }

        #if JOT_FLAVOR_1
        // Re-render the PFB section in place on every Flavor1Session state
        // transition (signedOut → signingIn → signedIn → expired). The
        // factory is pure and re-reads `Flavor1Session.shared.state` per
        // call, so we just need to swap the section items.
        flavor1StateCancellable = Flavor1Session.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildFlavor1Section()
            }
        #endif
    }

    // MARK: - Menu construction

    private func buildMenu() -> NSMenu {
        menu.autoenablesItems = false

        let toggle = NSMenuItem(
            title: Self.toggleTitle(for: recorder.state),
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.isEnabled = Self.toggleEnabled(for: recorder.state)
        menu.addItem(toggle)
        toggleItem = toggle

        #if JOT_FLAVOR_1
        // PFB Enterprise sign-in / refresh / disconnect section. Spliced in
        // right under the recording toggle so the auth-state affordance is
        // visible up high. Re-rendered on Flavor1Session state changes by
        // `rebuildFlavor1Section` — items are tracked in
        // `flavor1SectionItems` so the rebuild removes exactly what it
        // inserted, without disturbing surrounding items.
        installFlavor1Section()
        #endif

        menu.addItem(.separator())

        let copyLast = NSMenuItem(
            title: "Copy Last Transcription",
            action: #selector(copyLastTranscription),
            keyEquivalent: ""
        )
        copyLast.target = self
        copyLast.isEnabled = (recorder.lastTranscript?.isEmpty == false)
        menu.addItem(copyLast)
        copyLastItem = copyLast

        // Recent Transcriptions submenu — 10 most recent recordings, each
        // clickable to copy its transcript. Contents are rebuilt lazily in
        // `menuNeedsUpdate(_:)` (delegate-driven), so freshly-added
        // recordings show up the next time the user opens the submenu
        // without us having to subscribe to SwiftData change notifications.
        recentSubmenu.delegate = self
        recentSubmenu.autoenablesItems = false
        let recent = NSMenuItem(
            title: "Recent Transcriptions",
            action: nil,
            keyEquivalent: ""
        )
        recent.submenu = recentSubmenu
        menu.addItem(recent)

        let showWindow = NSMenuItem(
            title: "Open Jot…",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showWindow.target = self
        menu.addItem(showWindow)

        menu.addItem(.separator())

        let checkUpdates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkUpdates.target = self
        menu.addItem(checkUpdates)

        let quit = NSMenuItem(
            title: "Quit Jot",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    #if JOT_FLAVOR_1
    // MARK: - Flavor1 PFB Enterprise section

    /// Inserts the PFB Enterprise section (leading separator + section header
    /// + state-dependent rows) at the current end of the root menu. Called
    /// once during `buildMenu()` from inside the `#if JOT_FLAVOR_1` block,
    /// after the recording toggle item is appended.
    private func installFlavor1Section() {
        let separator = NSMenuItem.separator()
        menu.addItem(separator)
        flavor1SectionItems.append(separator)

        for item in Flavor1MenuItems.items(target: self) {
            menu.addItem(item)
            flavor1SectionItems.append(item)
        }
    }

    /// Removes the previously-inserted PFB section items and re-inserts a
    /// freshly-rendered section at the same anchor point. Driven by Combine
    /// emissions on `Flavor1Session.shared.$state`, so the menu reflects
    /// signed-out → signing-in → signed-in → expired transitions without
    /// requiring the user to re-open the menu.
    private func rebuildFlavor1Section() {
        guard let firstItem = flavor1SectionItems.first,
              let anchorIndex = menu.items.firstIndex(of: firstItem)
        else {
            // Section was never installed (or already torn down) — nothing
            // to rebuild. This branch should only fire if the menu was
            // mutated externally; logging is unnecessary noise.
            return
        }

        for item in flavor1SectionItems where menu.items.contains(item) {
            menu.removeItem(item)
        }
        flavor1SectionItems.removeAll(keepingCapacity: true)

        let separator = NSMenuItem.separator()
        menu.insertItem(separator, at: anchorIndex)
        flavor1SectionItems.append(separator)

        var insertAt = anchorIndex + 1
        for item in Flavor1MenuItems.items(target: self) {
            menu.insertItem(item, at: insertAt)
            flavor1SectionItems.append(item)
            insertAt += 1
        }
    }
    #endif

    // MARK: - Recent Transcriptions submenu

    private func populateRecentSubmenu() {
        recentSubmenu.removeAllItems()

        let recordings = fetchRecentRecordings(limit: 10)
        guard !recordings.isEmpty else {
            let empty = NSMenuItem(title: "No recordings yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentSubmenu.addItem(empty)
            return
        }

        for recording in recordings {
            let item = NSMenuItem(
                title: Self.previewTitle(for: recording),
                action: #selector(copyRecordingTranscript(_:)),
                keyEquivalent: ""
            )
            item.target = self
            // `representedObject` carries the UUID across into the click
            // handler; re-fetching by id avoids holding a SwiftData model
            // reference across the menu's lifecycle.
            item.representedObject = recording.id
            recentSubmenu.addItem(item)
        }

        recentSubmenu.addItem(.separator())
        let showAll = NSMenuItem(
            title: "Show All Recordings…",
            action: #selector(showRecordingsHome),
            keyEquivalent: ""
        )
        showAll.target = self
        recentSubmenu.addItem(showAll)
    }

    private func fetchRecentRecordings(limit: Int) -> [Recording] {
        var descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Compact one-line preview: "2 min ago · first 60 chars of transcript…".
    /// `RelativeDateTimeFormatter` handles the localized "X ago" phrasing.
    private static func previewTitle(for recording: Recording) -> String {
        let relative = relativeFormatter.localizedString(
            for: recording.createdAt,
            relativeTo: .now
        )
        let rawPreview = recording.transcript
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preview: String
        if rawPreview.isEmpty {
            preview = "(empty)"
        } else if rawPreview.count > 60 {
            preview = String(rawPreview.prefix(60)) + "…"
        } else {
            preview = rawPreview
        }
        return "\(relative) · \(preview)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    // MARK: - State reflection

    private func applyState(_ state: RecorderController.State) {
        toggleItem?.title = Self.toggleTitle(for: state)
        toggleItem?.isEnabled = Self.toggleEnabled(for: state)
        statusItem?.button?.toolTip = Self.accessibilityDescription(for: state)

        if let image = Self.icon(for: state) {
            image.isTemplate = true
            statusItem?.button?.image = image
        }
    }

    private static func toggleTitle(for state: RecorderController.State) -> String {
        switch state {
        case .idle: return "Start Recording"
        case .recording: return "Stop Recording"
        case .transcribing: return "Transcribing…"
        case .transforming: return "Cleaning up…"
        case .error: return "Retry"
        }
    }

    private static func toggleEnabled(for state: RecorderController.State) -> Bool {
        switch state {
        case .transcribing, .transforming: return false
        case .idle, .recording, .error: return true
        }
    }

    private static func icon(for state: RecorderController.State) -> NSImage? {
        if let image = bundledMenuBarIcon(named: stateIconName(for: state)) {
            return image
        }
        // Fall back to the state-agnostic icon if a specific state asset
        // is missing, then to the SF Symbol set.
        if let image = bundledMenuBarIcon(named: menuBarIconName) {
            return image
        }
        return fallbackSymbol(for: state)
    }

    private static func bundledMenuBarIcon(named name: NSImage.Name) -> NSImage? {
        guard let image = NSImage(named: name) else {
            return nil
        }

        let copiedImage = (image.copy() as? NSImage) ?? image
        copiedImage.isTemplate = true
        return copiedImage
    }

    private static func fallbackSymbol(for state: RecorderController.State) -> NSImage? {
        let symbolName: String
        switch state {
        case .idle: symbolName = "mic.fill"
        case .recording: symbolName = "mic.and.signal.meter.fill"
        case .transcribing: symbolName = "waveform"
        case .transforming: symbolName = "wand.and.stars"
        case .error: symbolName = "exclamationmark.triangle.fill"
        }

        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription(for: state)
        )
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return image?.withSymbolConfiguration(config)
    }

    private static func accessibilityDescription(for state: RecorderController.State) -> String {
        switch state {
        case .idle: return "Jot: idle"
        case .recording: return "Jot: recording"
        case .transcribing: return "Jot: transcribing"
        case .transforming: return "Jot: cleaning up"
        case .error: return "Jot: error"
        }
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        Task { @MainActor in
            await recorder.toggle()
        }
    }

    @objc private func copyLastTranscription() {
        guard let text = recorder.lastTranscript, !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Opens the unified "Jot" window with the given sidebar selection
    /// forced. Used by both `Open Jot…` (which forces `.home`) and
    /// `Settings…` (which forces `.settings(.general)`).
    ///
    /// Two paths, chosen by whether the window already exists:
    ///
    ///  • Cold-open (first time this session): write `selection` to
    ///    `JotAppWindow.pendingSelection` BEFORE ordering-front so the
    ///    SwiftUI scene picks it up as its initial `@State` value on
    ///    first render. This avoids a race where a notification posted
    ///    before the scene materializes would be dropped.
    ///
    ///  • Already open: post the `.jotWindowSetSidebarSelection`
    ///    notification so the running view's `.onReceive` observer
    ///    updates the existing selection.
    private func openUnifiedWindow(selection: AppSidebarSelection) {
        // Seed the cold-open buffer first. Harmless if the window is
        // already realized — `init` only runs for a new scene instance
        // and the buffer is nilled out after it's consumed.
        JotAppWindow.pendingSelection = selection

        NSApp.activate(ignoringOtherApps: true)

        // Find the unified window by id. SwiftUI stamps the scene id into
        // the `NSWindow.identifier`; a substring match is resilient to
        // AppKit's id-wrapping conventions across macOS versions.
        let target = NSApp.windows.first { window in
            window.identifier?.rawValue.contains("jot-main") == true
        }
        if let target {
            // Window already exists — clear the buffer (the scene's
            // `init` won't run again) and drive the selection change
            // through the notification path the view is observing.
            JotAppWindow.pendingSelection = nil
            NotificationCenter.default.post(
                name: .jotWindowSetSidebarSelection,
                object: nil,
                userInfo: ["selection": selection]
            )
            target.makeKeyAndOrderFront(nil)
        } else {
            // Fall back to the first main-capable window if the id lookup
            // misses (e.g. first-ever open in a session where SwiftUI has
            // not yet materialized the scene). AppKit will still route
            // `makeKeyAndOrderFront(nil)` via the responder chain to the
            // Window scene SwiftUI will instantiate — and the scene's
            // `init` will consume `pendingSelection` on first render.
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func showMainWindow() {
        openUnifiedWindow(selection: .home)
    }

    @objc private func checkForUpdates() {
        checkForUpdatesAction()
    }

    @objc private func showRecordingsHome() {
        openUnifiedWindow(selection: .home)
    }

    /// Menu-item click handler for a row inside the Recent Transcriptions
    /// submenu. Pulls the `UUID` from `representedObject`, re-fetches the
    /// Recording from SwiftData (fresh text even if edited inside the
    /// Home recordings list), and copies the transcript to the clipboard.
    @objc private func copyRecordingTranscript(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        var descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let recording = (try? modelContext.fetch(descriptor))?.first else { return }
        let text = recording.transcript
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSMenuDelegate

extension JotMenuBarController: NSMenuDelegate {
    /// Called by AppKit immediately before the menu is displayed. We only
    /// rebuild the `recentSubmenu` contents here — other menus have static
    /// shape and are built once in `buildMenu()`.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === recentSubmenu {
            populateRecentSubmenu()
        }
    }
}
