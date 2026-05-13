import AppKit
import Combine

/// Single-key global hotkey for one of the five `SingleKey.Action`s.
/// Lives alongside the existing `KeyboardShortcuts` (Carbon) chord
/// handler so users with a chord binding aren't disrupted — both can be
/// active at once and either fires the action.
///
/// Why this exists: Carbon's `RegisterEventHotKey` refuses bindings
/// without modifier keys, but a single key (Caps Lock, Fn, right
/// Option…) is a much faster and more discoverable trigger for new
/// users. macOS still delivers `.flagsChanged` events for those keys
/// system-wide as long as the app has Accessibility permission — which
/// Jot already requests for synthetic-paste delivery.
///
/// Lifecycle:
///   • `bind(key:mode:onStart:onStop:)` installs both a global and local
///     `NSEvent` monitor (covers events targeting other apps and our
///     own window respectively). Idempotent — calling again replaces
///     the active key, mode, and callbacks without leaking monitors.
///   • `unbind()` removes both monitors. Always paired with `bind`.
///
/// Trigger modes (see `SingleKey.Action.mode`):
///   • `.hold` — `onStart` fires on key press, `onStop` on release.
///     Push-to-talk semantics. For Caps Lock the "press" is the latched
///     flag's ON transition; "release" is its OFF transition — i.e.
///     consecutive Caps Lock taps alternate start/stop.
///   • `.toggle` — Caps Lock uses the same flag-edge semantics as hold
///     (it's natively a toggle). Every other key uses a *synthetic*
///     toggle: each press alternates between `onStart` and `onStop`;
///     releases are ignored.
///   • `.tap` — single-shot fire. `onStart` is called on each press;
///     `onStop` is unused (releases ignored). Caps Lock is never bound
///     in this mode (excluded from the picker).
@MainActor
final class SingleKeyHotkey {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activeKey: SingleKey = .none
    private var activeMode: SingleKey.TriggerMode = .hold
    private var onStart: (() -> Void)?
    private var onStop: (() -> Void)?

    /// For non-latched keys: tracks whether the bound modifier was held
    /// on the last event we saw, so we only act on ON↔OFF *transitions*.
    /// For Caps Lock this still works correctly because each user press
    /// flips the latched flag.
    private var lastWasActive: Bool = false

    /// Synthetic-toggle state for `.toggle` mode with a non-latched key.
    /// Flipped on each ON edge; decides whether the next press fires
    /// `onStart` (true) or `onStop` (false). Reset on every `bind()`.
    private var toggleInternal: Bool = false

    func bind(
        _ key: SingleKey,
        mode: SingleKey.TriggerMode,
        onStart: @escaping () -> Void,
        onStop: (() -> Void)? = nil
    ) {
        self.activeKey = key
        self.activeMode = mode
        self.onStart = onStart
        self.onStop = onStop
        // Seed `lastWasActive` from current modifier state so a binding
        // switch doesn't fire a spurious onStart/onStop on the first
        // event delivered.
        if let flag = key.modifierFlag {
            lastWasActive = NSEvent.modifierFlags.contains(flag)
        } else {
            lastWasActive = false
        }
        toggleInternal = false

        // Tear down + rebuild monitors only when transitioning to/from
        // `.none`. If we're swapping between two real keys, the existing
        // monitors stay live — they're keyCode-filtered in `handle(_:)`.
        if key == .none {
            removeMonitors()
            return
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                Task { @MainActor [weak self] in self?.handle(event) }
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                Task { @MainActor [weak self] in self?.handle(event) }
                return event
            }
        }
    }

    func unbind() {
        activeKey = .none
        activeMode = .hold
        onStart = nil
        onStop = nil
        removeMonitors()
    }

    private func removeMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    private func handle(_ event: NSEvent) {
        guard let modifierFlag = activeKey.modifierFlag,
              activeKey.keyCodes.contains(event.keyCode)
        else { return }
        let isActive = event.modifierFlags.contains(modifierFlag)
        guard isActive != lastWasActive else { return }
        let edgeIsOn = isActive
        lastWasActive = isActive

        switch activeMode {
        case .hold:
            // Fire on every transition. For Caps Lock this is naturally
            // toggle (each user press alternates the latched flag); for
            // momentary keys it's push-to-talk.
            if edgeIsOn { onStart?() } else { onStop?() }

        case .toggle:
            if activeKey.isLatched {
                // Caps Lock — same edge semantics as hold mode. The
                // latched flag IS the toggle state.
                if edgeIsOn { onStart?() } else { onStop?() }
            } else {
                // Synthetic toggle. Only ON edges flip state; OFF edges
                // (release) are ignored so the user doesn't have to keep
                // the modifier held.
                guard edgeIsOn else { return }
                toggleInternal.toggle()
                if toggleInternal { onStart?() } else { onStop?() }
            }

        case .tap:
            // Single-shot fire on press. Release ignored — `onStop` is
            // not consulted in this mode.
            if edgeIsOn { onStart?() }
        }
    }
}
