import KeyboardShortcuts
import SwiftUI

struct ShortcutsPane: View {
    // The pane observes KeyboardShortcuts changes via its onShortcutChange hook
    // so the conflict banner and Recorders reflect edits as they happen.
    @Environment(\.helpNavigator) private var navigator
    @State private var refreshToken: Int = 0

    // One @AppStorage per `SingleKey.Action` — SwiftUI needs literal
    // string keys at compile time, so we can't drive these off the enum
    // directly. The values match `SingleKey.Action.<case>.storageKey`.
    @AppStorage("jot.hotkey.toggleRecording.singleKey") private var toggleSingleKey: SingleKey = .none
    @AppStorage("jot.hotkey.pushToTalk.singleKey") private var pushToTalkSingleKey: SingleKey = .none
    @AppStorage("jot.hotkey.pasteLastTranscription.singleKey") private var pasteLastSingleKey: SingleKey = .none
    @AppStorage("jot.hotkey.rewriteWithVoice.singleKey") private var rewriteWithVoiceSingleKey: SingleKey = .none
    @AppStorage("jot.hotkey.rewrite.singleKey") private var rewriteSingleKey: SingleKey = .none

    var body: some View {
        let _ = refreshToken
        return ScrollViewReader { proxy in
            Form {
                Section {
                    HStack(alignment: .top) {
                        Text("Global shortcuts fire from any app when Input Monitoring is granted. Each action lets you bind a single key, a chord (⌘⌥⌃⇧ + key), or both — either will fire it.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        InfoPopoverButton(
                            title: "Global shortcuts",
                            body: "Single-key bindings (Caps Lock, Fn, side-modifiers) listen via NSEvent and require Accessibility permission. Chord bindings go through Carbon's hot-key API and must include at least one modifier (⌘ ⌥ ⌃ ⇧). Each row's single-key picker and chord recorder are independent — bind either or both.",
                            helpAnchor: "modifier-required"
                        )
                    }
                }

                shortcutSection(
                    action: .toggleRecording,
                    keyboardShortcutsName: .toggleRecording,
                    singleKey: $toggleSingleKey,
                    modeDescription: "Tap to start recording, tap again to stop.",
                    rowAnchor: "toggle-recording"
                )

                shortcutSection(
                    action: .pushToTalk,
                    keyboardShortcutsName: .pushToTalk,
                    singleKey: $pushToTalkSingleKey,
                    modeDescription: "Hold to record, release to stop and transcribe.",
                    rowAnchor: "push-to-talk"
                )

                shortcutSection(
                    action: .pasteLastTranscription,
                    keyboardShortcutsName: .pasteLastTranscription,
                    singleKey: $pasteLastSingleKey,
                    modeDescription: "Single tap pastes the last transcript at the cursor.",
                    rowAnchor: nil
                )

                shortcutSection(
                    action: .rewriteWithVoice,
                    keyboardShortcutsName: .rewriteWithVoice,
                    singleKey: $rewriteWithVoiceSingleKey,
                    modeDescription: "Select text first. Tap to dictate an instruction; tap again to send.",
                    rowAnchor: nil
                )

                shortcutSection(
                    action: .rewrite,
                    keyboardShortcutsName: .rewrite,
                    singleKey: $rewriteSingleKey,
                    modeDescription: "Select text first. Single tap applies the built-in rewrite prompt.",
                    rowAnchor: nil
                )

                Section("Cancel recording") {
                    HStack {
                        Text("Cancel")
                        Spacer()
                        Text("esc")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                            .foregroundStyle(.secondary)
                        InfoPopoverButton(
                            title: "Cancel recording",
                            body: "Press Escape to cancel an active recording, transform, or rewrite. Hardcoded and not configurable — only active while Jot is mid-capture.",
                            helpAnchor: "cancel-recording"
                        )
                    }
                }

                if let conflict = conflictMessage() {
                    Section {
                        Label(conflict, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Reset to defaults", action: resetToDefaults)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { consumePendingSettingsFieldAnchor(with: proxy) }
            .onChange(of: navigator.pendingSettingsFieldAnchor) { _, _ in
                consumePendingSettingsFieldAnchor(with: proxy)
            }
        }
    }

    // MARK: - One section per action

    @ViewBuilder
    private func shortcutSection(
        action: SingleKey.Action,
        keyboardShortcutsName: KeyboardShortcuts.Name,
        singleKey: Binding<SingleKey>,
        modeDescription: String,
        rowAnchor: String?
    ) -> some View {
        Section(action.displayName) {
            singleKeyRow(action: action, selection: singleKey, anchor: rowAnchor)
            chordRow(action: action, keyboardShortcutsName: keyboardShortcutsName)
            Text(modeDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func singleKeyRow(
        action: SingleKey.Action,
        selection: Binding<SingleKey>,
        anchor: String?
    ) -> some View {
        let row = HStack {
            Text("Single key")
            Spacer()
            singleKeyMenu(action: action, selection: selection)
            InfoPopoverButton(
                title: "Single-key trigger",
                body: singleKeyPopoverBody(for: action),
                helpAnchor: helpAnchor(for: action)
            )
        }
        if let anchor {
            row.id(anchor)
        } else {
            row
        }
    }

    @ViewBuilder
    private func singleKeyMenu(
        action: SingleKey.Action,
        selection: Binding<SingleKey>
    ) -> some View {
        let conflicts = singleKeyConflicts(excluding: action)
        Menu {
            Button("None") { selection.wrappedValue = .none }
            Divider()
            ForEach(action.pickerCases) { key in
                let conflict = conflicts[key]
                Button {
                    selection.wrappedValue = key
                } label: {
                    if let conflict {
                        Text("\(key.displayName) — used by \(conflict.displayName)")
                    } else {
                        Text(key.displayName)
                    }
                }
                .disabled(conflict != nil && selection.wrappedValue != key)
            }
        } label: {
            Text(selection.wrappedValue.displayName)
                .frame(minWidth: 180, alignment: .trailing)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func chordRow(
        action: SingleKey.Action,
        keyboardShortcutsName: KeyboardShortcuts.Name
    ) -> some View {
        HStack {
            Text("Chord")
            Spacer()
            KeyboardShortcuts.Recorder(for: keyboardShortcutsName) { _ in
                refreshToken &+= 1
            }
            InfoPopoverButton(
                title: "Chord shortcut",
                body: chordPopoverBody(for: action),
                helpAnchor: helpAnchor(for: action)
            )
        }
    }

    // MARK: - Mutual-exclusion + conflict computation

    /// Returns a dict of "this single-key is currently bound to that
    /// action," excluding `excludedAction` so a row's own current
    /// selection isn't marked as a conflict against itself.
    private func singleKeyConflicts(
        excluding excludedAction: SingleKey.Action
    ) -> [SingleKey: SingleKey.Action] {
        var result: [SingleKey: SingleKey.Action] = [:]
        for action in SingleKey.Action.allCases where action != excludedAction {
            let key = singleKeyValue(for: action)
            if key != .none {
                result[key] = action
            }
        }
        return result
    }

    private func singleKeyValue(for action: SingleKey.Action) -> SingleKey {
        switch action {
        case .toggleRecording:        return toggleSingleKey
        case .pushToTalk:             return pushToTalkSingleKey
        case .pasteLastTranscription: return pasteLastSingleKey
        case .rewriteWithVoice:       return rewriteWithVoiceSingleKey
        case .rewrite:                return rewriteSingleKey
        }
    }

    /// Chord conflicts — same shortcut bound to multiple actions.
    /// Extended from the original 4-binding banner to cover all 5
    /// `KeyboardShortcuts.Name`s shown in this pane.
    private func conflictMessage() -> String? {
        var seen: [KeyboardShortcuts.Shortcut: [String]] = [:]
        for action in SingleKey.Action.allCases {
            let name = keyboardShortcutsName(for: action)
            if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
                seen[shortcut, default: []].append(action.displayName)
            }
        }
        let duplicates = seen.filter { $0.value.count > 1 }
        guard let first = duplicates.first else { return nil }
        return "Conflict: \(first.value.joined(separator: " and ")) share the same chord."
    }

    private func keyboardShortcutsName(for action: SingleKey.Action) -> KeyboardShortcuts.Name {
        switch action {
        case .toggleRecording:        return .toggleRecording
        case .pushToTalk:             return .pushToTalk
        case .pasteLastTranscription: return .pasteLastTranscription
        case .rewriteWithVoice:       return .rewriteWithVoice
        case .rewrite:                return .rewrite
        }
    }

    // MARK: - Popover copy

    private func singleKeyPopoverBody(for action: SingleKey.Action) -> String {
        switch action {
        case .toggleRecording:
            return "Caps Lock is the recommended single-key — the keyboard LED becomes your recording indicator. Fn or a side modifier (right ⌥, right ⌘, …) also work as toggle: tap to start, tap to stop."
        case .pushToTalk:
            return "Pick a modifier key — Fn, right ⌥/⌘/⇧/⌃, or a side-agnostic ⌥/⌘/⇧/⌃. Hold the key to record, release to stop. Same shape as walkie-talkie."
        case .pasteLastTranscription:
            return "Single tap of the bound modifier pastes the last transcript at the cursor. Each tap fires once — holding doesn't repeat."
        case .rewriteWithVoice:
            return "Select text in any app, tap the bound modifier to start dictating an instruction, tap again to send to the LLM and paste the rewrite back. Caps-Lock-style toggle."
        case .rewrite:
            return "Select text in any app, single tap the bound modifier to apply the built-in rewrite prompt and paste the result back. No voice instruction step."
        }
    }

    private func chordPopoverBody(for action: SingleKey.Action) -> String {
        let chordDefinition = "A chord is a multi-key global hotkey — at least one modifier (⌘ ⌥ ⌃ ⇧) plus another key, like ⌥Space. Click the recorder field, then press the keys you want."
        switch action {
        case .toggleRecording:
            return "\(chordDefinition) Fires the same start/stop as the single-key trigger; either or both can be bound."
        case .pushToTalk:
            return "\(chordDefinition) Hold the chord to record; release to stop and transcribe."
        case .pasteLastTranscription:
            return "\(chordDefinition) Single press pastes the last transcript at the cursor."
        case .rewriteWithVoice:
            return "\(chordDefinition) Select text in any app, hold the chord, speak an instruction — Jot rewrites the selection with your configured LLM and pastes it back."
        case .rewrite:
            return "\(chordDefinition) Select text in any app, press the chord — Jot applies the built-in rewrite prompt and pastes the result back."
        }
    }

    private func helpAnchor(for action: SingleKey.Action) -> String {
        switch action {
        case .toggleRecording:        return "toggle-recording"
        case .pushToTalk:             return "push-to-talk"
        case .pasteLastTranscription: return "dictation"
        case .rewriteWithVoice:       return "articulate-custom"
        case .rewrite:                return "articulate-fixed"
        }
    }

    // MARK: - Reset / deep-link scroll

    private func resetToDefaults() {
        KeyboardShortcuts.reset(
            .toggleRecording,
            .pushToTalk,
            .pasteLastTranscription,
            .rewriteWithVoice,
            .rewrite
        )
        // Reset single-keys: Caps Lock for Toggle Recording (matches
        // `SingleKeyMigration` for fresh installs), `.none` for the rest.
        toggleSingleKey = .capsLock
        pushToTalkSingleKey = .none
        pasteLastSingleKey = .none
        rewriteWithVoiceSingleKey = .none
        rewriteSingleKey = .none
        // Clear Toggle Recording chord — matches fresh-install defaults
        // where Caps Lock is the sole binding. The other four actions
        // keep their KeyboardShortcuts library defaults from `.reset(…)`.
        KeyboardShortcuts.setShortcut(nil, for: .toggleRecording)
        refreshToken &+= 1
    }

    private func consumePendingSettingsFieldAnchor(with proxy: ScrollViewProxy) {
        guard let anchor = navigator.pendingSettingsFieldAnchor,
              anchor == "toggle-recording" || anchor == "push-to-talk"
        else { return }
        withAnimation {
            proxy.scrollTo(anchor, anchor: .top)
        }
        navigator.clearPendingSettingsFieldAnchor()
    }
}
