import Foundation
import SwiftData
import SwiftUI

public enum LogWorstState {
    case clean
    case yellow
    case red
    var isClean: Bool { if case .clean = self { return true }; return false }
    var isRed: Bool { if case .red = self { return true }; return false }
}

@MainActor
final class LogScanner: ObservableObject {
    @Published private(set) var visibleResults: [PrivacyCheckResult] = []
    @Published private(set) var isComplete: Bool = false
    @Published private(set) var stats: String = ""
    @Published private(set) var worst: LogWorstState = .clean

    private var allResults: [PrivacyCheckResult] = []
    private let modelContext: ModelContext?
    private let llmConfiguration: LLMConfiguration

    init(modelContext: ModelContext? = nil, llmConfiguration: LLMConfiguration) {
        self.modelContext = modelContext
        self.llmConfiguration = llmConfiguration
    }

    func run() async {
        let start = Date()
        let logURL = ErrorLog.logFileURL
        let contents = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let byteSize = contents.utf8.count

        let config = llmConfiguration
        let keys = LLMConfiguration.bucketedProviders.map { config.apiKey(for: $0) }
        let baseURLs = LLMConfiguration.bucketedProviders.map { config.baseURL(for: $0) }
        let transcripts = fetchTranscripts()
        let home = NSHomeDirectory()

        let results = PrivacyScanner.scan(
            logContents: contents,
            currentAPIKeys: keys,
            customBaseURLs: baseURLs,
            knownTranscripts: transcripts,
            homeDirectory: home
        )
        allResults = results

        // Sequentially reveal each result with 3 second delay between reveals
        for r in results {
            withAnimation { visibleResults.append(r) }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }

        // Compute worst state
        let red: Set<PrivacyCheckKind> = [.apiKeys, .credentialURLs]
        var state: LogWorstState = .clean
        for r in results where !r.isClean {
            if red.contains(r.kind) { state = .red; break }
            state = .yellow
        }
        worst = state

        let ms = Int(Date().timeIntervalSince(start) * 1000)
        stats = "Scanned \(byteSize / 1024) KB in \(ms) ms"
        isComplete = true
    }

    private func fetchTranscripts() -> [String] {
        guard let ctx = modelContext else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date.distantPast
        var descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.createdAt >= cutoff }
        )
        descriptor.fetchLimit = 2000
        var all: [String] = []
        var seen = Set<String>()
        let appendIfSensitive: (String) -> Void = { s in
            guard s.count >= 10 else { return }
            guard seen.insert(s).inserted else { return }
            all.append(s)
        }
        if let recordings = try? ctx.fetch(descriptor) {
            for r in recordings {
                appendIfSensitive(r.transcript)
                if r.rawTranscript != r.transcript { appendIfSensitive(r.rawTranscript) }
            }
        }
        // Rewrite sessions carry user-selected text + voice instructions +
        // LLM output that must participate in log redaction with the same
        // count >= 10 threshold as the dictation transcript fields. Without
        // this, a Rewrite selection ("my client said X about Y") that
        // incidentally appears in any log line would not be redacted — a
        // privacy regression vs. dictation. Identical strings across
        // selectionText / instructionText / output (or across sessions)
        // are deduped via `seen` so `LogRedactor` doesn't apply the same
        // range twice against a mutating string.
        var sessionDescriptor = FetchDescriptor<RewriteSession>(
            predicate: #Predicate { $0.createdAt >= cutoff }
        )
        sessionDescriptor.fetchLimit = 2000
        if let sessions = try? ctx.fetch(sessionDescriptor) {
            for s in sessions {
                appendIfSensitive(s.selectionText)
                appendIfSensitive(s.instructionText)
                appendIfSensitive(s.output)
            }
        }
        return all
    }

    var currentContents: String {
        (try? String(contentsOf: ErrorLog.logFileURL, encoding: .utf8)) ?? ""
    }

    func redactedContents() -> String {
        let (redacted, _) = LogRedactor.redact(currentContents, using: allResults)
        return redacted
    }
}
