import Foundation
import KeyboardShortcuts

/// One-shot migration on the first launch of the build that introduced
/// `SingleKey` bindings for `.toggleRecording`. Gated by an
/// `@AppStorage`-style boolean so it runs exactly once per install.
///
/// Policy:
///   • **Fresh install** (`FirstRunState.setupComplete == false`) →
///     default to `SingleKey.capsLock` and clear the chord binding so
///     the user's only out-of-the-box hotkey is Caps Lock. The Setup
///     Wizard's Test step shows Caps Lock and walks them through
///     pressing it.
///   • **Existing user** (`setupComplete == true`) → leave their chord
///     binding alone (whether they were on the `⌥Space` default or
///     customized to anything else) and start `SingleKey` at `.none`.
///     They're not surprised; they keep what they had. Caps Lock is
///     opt-in from Settings → Shortcuts.
///
/// We use raw `UserDefaults` reads here rather than `@AppStorage` so the
/// migration can run from `AppDelegate.applicationDidFinishLaunching`
/// before any SwiftUI view has materialized.
@MainActor
enum SingleKeyMigration {
    private static let migratedKey = "jot.hotkey.toggleRecording.migrated"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)

        if FirstRunState.shared.setupComplete {
            // Existing user — leave chord, single-key starts at None.
            // No-op; the @AppStorage default of `.none` is correct.
        } else {
            // Fresh install — Caps Lock is the new default toggle.
            defaults.set(SingleKey.capsLock.rawValue, forKey: SingleKey.storageKey)
            // Clear the library's `⌥Space` default so the user's only
            // out-of-the-box hotkey is Caps Lock. `setShortcut(nil, ...)`
            // explicitly disables the binding; `KeyboardShortcuts`
            // treats this as "user opted out of the default."
            KeyboardShortcuts.setShortcut(nil, for: .toggleRecording)
        }
    }
}
