import Foundation

/// One-shot UserDefaults migrations that decide which `ParakeetModelID` is
/// the user's primary at launch.
///
/// Two helpers, run at different release boundaries:
///
/// - `runV17PinIfNeeded` — v1.7's quiet pin. Writes `jot.defaultModelID =
///   "tdt_0_6b_v3"` for *returning* users with no explicit key, so v2.0's
///   classifier later sees an explicit choice and never silently swaps the
///   user onto streaming. Fresh v1.7 installs leave the key absent.
///
/// - `runV20DefaultStampIfNeeded` — v2.0's first-launch classifier. Writes
///   either the streaming default (genuine fresh install) or v3 (returning
///   user who skipped v1.7). Persists the result so the choice doesn't drift
///   between launches as the freshness heuristic flips on first recording.
///
/// Both share the same `isFreshInstall` heuristic (§3.4.4): any one of an
/// explicit key, a cached v3/JA bundle, or a non-empty recordings directory
/// classifies the user as returning. `installedModelIDs` and
/// `recordingsDirectoryEmpty` are passed in so tests can stub them without
/// touching the dev/CI machine's real cache or `~/Library/Application
/// Support/Jot/Recordings/`.
///
/// Both migrations are idempotent — they record `pinChecked` /
/// `v2DefaultStamped` markers and exit early on subsequent launches.
///
/// `@MainActor`-isolated because the migration reads
/// `TranscriberHolder.defaultsKey`, which is itself MainActor-isolated.
/// `JotComposition.build` is the only call site and is already MainActor,
/// so the annotation is free.
@MainActor
enum ModelChoiceMigration {

    /// UserDefaults key marking that v1.7's one-shot pin migration has
    /// already evaluated this user. Set on every v1.7+ launch so a fresh
    /// install that later downloads v3 in the wizard doesn't get
    /// retroactively pinned on its second launch.
    static let pinCheckedKey = "jot.modelChoice.pinChecked"

    /// UserDefaults key marking that v2.0's first-launch classifier has run.
    /// Without this marker, the classifier would re-evaluate every launch
    /// and silently flip the user's primary as recordings accumulate
    /// (fresh → returning) — see §3.4.3.
    static let v2DefaultStampedKey = "jot.modelChoice.v2DefaultStamped"

    /// v1.7 pin. Idempotent: records `pinChecked = true` on every run, even
    /// when the body short-circuits on an existing explicit key, so a second
    /// launch never re-classifies the user.
    ///
    /// - Returns: `true` when this call wrote `jot.defaultModelID`. Tests
    ///   read this to assert the four-step ordering. Production callers can
    ///   ignore the return value.
    @discardableResult
    static func runV17PinIfNeeded(
        defaults: UserDefaults,
        installedModelIDs: Set<ParakeetModelID>,
        recordingsDirectoryEmpty: Bool
    ) -> Bool {
        if defaults.bool(forKey: pinCheckedKey) {
            return false
        }
        defer { defaults.set(true, forKey: pinCheckedKey) }

        if defaults.string(forKey: TranscriberHolder.defaultsKey) != nil {
            return false
        }
        if isFreshInstall(
            defaults: defaults,
            installedModelIDs: installedModelIDs,
            recordingsDirectoryEmpty: recordingsDirectoryEmpty
        ) {
            return false
        }
        defaults.set(ParakeetModelID.tdt_0_6b_v3.rawValue, forKey: TranscriberHolder.defaultsKey)
        return true
    }

    /// v2.0 first-launch classifier (§3.4.3). Stamps `jot.defaultModelID`
    /// once per install with one of three outcomes:
    ///
    /// 1. `v2DefaultStamped == true` → no-op (already classified).
    /// 2. Explicit `jot.defaultModelID` already set → set the marker
    ///    and exit, leaving the user's choice intact (covers v1.7
    ///    pinned users, JA users, and post-v2.0 manual changes).
    /// 3. Returning user with no key (v1.7-skipper grandfather path)
    ///    → write `tdt_0_6b_v3`.
    /// 4. Genuine fresh install → write `tdt_0_6b_v2_en_streaming`.
    ///
    /// Persisting the classification is what prevents drift: a naive
    /// read-only fallback on `nil` would re-evaluate every launch and
    /// silently swap the user's primary as recordings accumulate.
    ///
    /// Phase 3 wires this into `JotComposition.build`. Phase 1 lands
    /// the helper unwired so the streaming case (which is hidden from
    /// `visibleCases`) doesn't get stamped before the UI can render it.
    ///
    /// - Returns: `true` when this call wrote `jot.defaultModelID`.
    @discardableResult
    static func runV20DefaultStampIfNeeded(
        defaults: UserDefaults,
        installedModelIDs: Set<ParakeetModelID>,
        recordingsDirectoryEmpty: Bool
    ) -> Bool {
        if defaults.bool(forKey: v2DefaultStampedKey) {
            return false
        }
        defer { defaults.set(true, forKey: v2DefaultStampedKey) }

        if defaults.string(forKey: TranscriberHolder.defaultsKey) != nil {
            return false
        }
        let target: ParakeetModelID = isFreshInstall(
            defaults: defaults,
            installedModelIDs: installedModelIDs,
            recordingsDirectoryEmpty: recordingsDirectoryEmpty
        )
            ? .tdt_0_6b_v2_en_streaming
            : .tdt_0_6b_v3
        defaults.set(target.rawValue, forKey: TranscriberHolder.defaultsKey)
        return true
    }

    /// Shared §3.4.4 freshness heuristic. Returns `true` only when *all*
    /// returning-user signals are absent — no explicit key, no cached
    /// Parakeet bundle, no recordings on disk.
    static func isFreshInstall(
        defaults: UserDefaults,
        installedModelIDs: Set<ParakeetModelID>,
        recordingsDirectoryEmpty: Bool
    ) -> Bool {
        if defaults.string(forKey: TranscriberHolder.defaultsKey) != nil { return false }
        if !installedModelIDs.isEmpty { return false }
        if !recordingsDirectoryEmpty { return false }
        return true
    }
}
