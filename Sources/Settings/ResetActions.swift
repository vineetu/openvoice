import AppKit
import Foundation
import KeyboardShortcuts
import SwiftUI

@MainActor
enum ResetActions {
    private static var pendingHardResetMarkerURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(".com.jot.Jot.pendingHardReset")
    }

    /// Phase 4 patch round 3: `keychain` seam threaded so per-provider
    /// API key deletion routes through `KeychainStoring` (production:
    /// `LiveKeychain`; harness: `StubKeychain`) instead of the static
    /// `KeychainHelper`. Closes the Phase 3 #29 Scope-A deferral.
    static func softReset(keychain: any KeychainStoring) {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        clearAPIKeys(keychain: keychain)
        FirstRunState.shared.reset()

        KeyboardShortcuts.reset(
            .toggleRecording,
            .pasteLastTranscription,
            .rewrite,
            .rewriteWithVoice,
            .pushToTalk
        )

        RestartHelper.relaunch()
    }

    static func hardReset(keychain: any KeychainStoring) {
        // Marker FILE (not UserDefaults) survives softReset's
        // removePersistentDomain call. processPendingHardReset on
        // next launch checks for this file and runs the wipe.
        do {
            try Data().write(to: pendingHardResetMarkerURL)
        } catch {
            Task { await ErrorLog.shared.error(component: "ResetActions", message: "hardReset failed to write marker file", context: ["error": ErrorLog.redactedAppleError(error)]) }
        }
        softReset(keychain: keychain)
    }

    /// Delete every per-provider API key + the legacy shared entry via
    /// the `KeychainStoring` seam. Internal so regression tests can
    /// exercise the seam-routing without firing `RestartHelper.relaunch()`.
    static func clearAPIKeys(keychain: any KeychainStoring) {
        // Legacy shared keychain entry (pre per-provider refactor).
        try? keychain.delete(account: "jot.llm.apiKey")
        // Per-provider keychain entries.
        for provider in LLMConfiguration.bucketedProviders {
            try? keychain.delete(account: "jot.llm.\(provider.rawValue).apiKey")
        }
    }

    static func resetPermissions() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jot.Jot"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "All", bundleID]
        try? task.run()
        task.waitUntilExit()
        RestartHelper.relaunch()
    }

    static func processPendingHardReset() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: pendingHardResetMarkerURL.path) else { return }
        try? fm.removeItem(at: pendingHardResetMarkerURL)

        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first!
        try? fm.removeItem(at: appSupport.appendingPathComponent("Jot"))
        try? fm.removeItem(at: appSupport.appendingPathComponent("FluidAudio"))
        try? fm.removeItem(at: appSupport.appendingPathComponent("default.store"))
        try? fm.removeItem(at: appSupport.appendingPathComponent("default.store-shm"))
        try? fm.removeItem(at: appSupport.appendingPathComponent("default.store-wal"))
        try? fm.removeItem(at: library.appendingPathComponent("Logs/Jot"))
        if let bundleID = Bundle.main.bundleIdentifier {
            try? fm.removeItem(at: library.appendingPathComponent("Caches/\(bundleID)"))
            try? fm.removeItem(at: library.appendingPathComponent("HTTPStorages/\(bundleID)"))
        }
    }
}
