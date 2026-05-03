import KeyboardShortcuts
import SwiftUI

struct ShortcutsPane: View {
    // The pane observes KeyboardShortcuts changes via its onShortcutChange hook
    // so the conflict banner and Recorders reflect edits as they happen.
    @Environment(\.helpNavigator) private var navigator
    @State private var refreshToken: Int = 0

    private static let bindings: [(KeyboardShortcuts.Name, String)] = [
        (.toggleRecording, "Toggle recording"),
        (.pushToTalk, "Push to talk (hold)"),
        (.pasteLastTranscription, "Paste last transcription"),
        (.rewriteWithVoice, "Rewrite with Voice"),
        (.rewrite, "Rewrite"),
    ]

    var body: some View {
        let _ = refreshToken
        return ScrollViewReader { proxy in
            Form {
                Section {
                    HStack(alignment: .top) {
                        Text("Global shortcuts fire from any app when Input Monitoring is granted.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        InfoPopoverButton(
                            title: "Global shortcuts",
                            body: "macOS requires shortcuts to include at least one modifier key (⌘, ⌥, ⌃, or ⇧). Bare single-key bindings like F5 or A alone are not supported and the recorder will reject them.",
                            helpAnchor: "modifier-required"
                        )
                    }
                }

                Section {
                    ForEach(Self.bindings, id: \.0) { name, label in
                        HStack {
                            Text(label)
                            Spacer()
                            KeyboardShortcuts.Recorder(for: name) { _ in
                                refreshToken &+= 1
                            }
                            InfoPopoverButton(
                                title: label,
                                body: popoverBody(for: name),
                                helpAnchor: helpAnchor(for: name)
                            )
                        }
                        .id(settingsAnchor(for: name) ?? "shortcut-\(label)")
                    }

                    HStack {
                        Text("Cancel recording")
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

    private func popoverBody(for name: KeyboardShortcuts.Name) -> String {
        switch name {
        case .toggleRecording:
            return "Press to start recording; press again to stop and transcribe. The primary dictation hotkey. Fires globally from any app."
        case .pushToTalk:
            return "Hold to record; release to transcribe. Prefer this when you want precise control over the capture window."
        case .pasteLastTranscription:
            return "Paste the most recent transcript again at the cursor. Handy when you need the same text in multiple places."
        case .rewriteWithVoice:
            return "Select text in any app, press this shortcut, speak an instruction — Jot rewrites the selection with your configured LLM and pastes it back."
        case .rewrite:
            return "Apply a built-in rewrite prompt to the selected text — no voice needed. Press the shortcut with text selected and Jot pastes the result back."
        default:
            return "A global hotkey. Requires at least one modifier key (⌘, ⌥, ⌃, or ⇧)."
        }
    }

    /// Per-binding Help slug. Each binding deep-links to the most
    /// specific feature card for its concept; `pasteLastTranscription`
    /// falls back to the Dictation hero because no dedicated sub-row
    /// exists for it in the current Feature registry.
    private func helpAnchor(for name: KeyboardShortcuts.Name) -> String {
        switch name {
        case .toggleRecording:          return "toggle-recording"
        case .pushToTalk:               return "push-to-talk"
        case .pasteLastTranscription:   return "dictation"
        case .rewriteWithVoice:         return "articulate-custom"
        case .rewrite:                  return "articulate-fixed"
        default:                        return "dictation"
        }
    }

    private func settingsAnchor(for name: KeyboardShortcuts.Name) -> String? {
        switch name {
        case .toggleRecording: return "toggle-recording"
        case .pushToTalk:      return "push-to-talk"
        default:               return nil
        }
    }

    private func conflictMessage() -> String? {
        var seen: [KeyboardShortcuts.Shortcut: [String]] = [:]
        for (name, label) in Self.bindings {
            if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
                seen[shortcut, default: []].append(label)
            }
        }
        let duplicates = seen.filter { $0.value.count > 1 }
        guard let first = duplicates.first else { return nil }
        return "Conflict: \(first.value.joined(separator: " and ")) share the same binding."
    }

    private func resetToDefaults() {
        KeyboardShortcuts.reset(
            .toggleRecording,
            .pushToTalk,
            .pasteLastTranscription,
            .rewriteWithVoice,
            .rewrite
        )
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
