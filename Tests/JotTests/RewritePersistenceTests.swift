import Foundation
import SwiftData
import Testing
@testable import Jot

/// Phase B persistence regression coverage, isolated to in-memory
/// SwiftData containers so tests don't touch the user's real
/// `default.store`:
///
/// 1. `RetentionService` purges expired `RewriteSession` rows alongside
///    `Recording` rows (plan §4 correctness fix — the original early-
///    return on `Recording.isEmpty` would have left rewrite-only data
///    untouched indefinitely).
/// 2. `RetentionService` purges rewrite-only data (regression test for
///    the early-return bug above).
/// 3. `RewriteSession` schema round-trip (with and without `modelUsed`).
/// 4. `RewriteSession.defaultTitle` semantics.
///
/// These tests construct `ModelContainer(... isStoredInMemoryOnly: true)`
/// directly rather than going through `JotHarness` — they only exercise
/// SwiftData + the Library helpers, no controller graph required.
@MainActor
@Suite(.serialized)
struct RewritePersistenceTests {

    private static func inMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Recording.self, RewriteSession.self,
            configurations: config
        )
    }

    private static func eightDaysAgo() -> Date {
        Date().addingTimeInterval(-8 * 86_400)
    }

    private static func now() -> Date { Date() }

    // MARK: - Retention

    /// Plan §4 correctness fix: when both kinds of expired rows exist,
    /// purge both in one pass. Pre-fix the early-return on Recording-only
    /// emptiness would have skipped the RewriteSession sweep.
    @Test func retentionPurgesBothKinds() throws {
        let container = try Self.inMemoryContainer()
        let context = container.mainContext

        // One expired Recording (8 days old; default retention is 7).
        let expiredRecording = Recording(
            id: UUID(),
            createdAt: Self.eightDaysAgo(),
            title: "old",
            durationSeconds: 1,
            transcript: "old transcript",
            rawTranscript: "old transcript",
            audioFileName: "nonexistent.wav",
            modelIdentifier: "tdt_0_6b_v3"
        )
        // One expired RewriteSession (same age).
        let expiredSession = RewriteSession(
            id: UUID(),
            createdAt: Self.eightDaysAgo(),
            flavor: "fixed",
            selectionText: "old selection",
            instructionText: "Rewrite this",
            output: "old output",
            modelUsed: "OpenAI · gpt-5.4-mini",
            title: "old session"
        )
        // One fresh RewriteSession that must SURVIVE the purge.
        let freshSession = RewriteSession(
            id: UUID(),
            createdAt: Self.now(),
            flavor: "voice",
            selectionText: "fresh selection",
            instructionText: "make it shorter",
            output: "fresh output",
            modelUsed: "Apple Intelligence (on-device)",
            title: "fresh session"
        )
        context.insert(expiredRecording)
        context.insert(expiredSession)
        context.insert(freshSession)
        try context.save()

        let prior = UserDefaults.standard.object(forKey: "jot.retentionDays")
        defer {
            if let v = prior {
                UserDefaults.standard.set(v, forKey: "jot.retentionDays")
            } else {
                UserDefaults.standard.removeObject(forKey: "jot.retentionDays")
            }
        }
        UserDefaults.standard.set(7, forKey: "jot.retentionDays")
        let service = RetentionService(context: context)
        service.purgeOnce()

        let recordingsAfter = try context.fetch(FetchDescriptor<Recording>())
        let sessionsAfter = try context.fetch(FetchDescriptor<RewriteSession>())

        #expect(recordingsAfter.isEmpty)
        #expect(sessionsAfter.count == 1)
        #expect(sessionsAfter.first?.title == "fresh session")
    }

    /// Regression for plan §4: a rewrite-only library that has expired
    /// data but no Recording rows must still get purged. Pre-fix the
    /// early-return on `Recording.isEmpty` would have left this data in
    /// place forever.
    @Test func retentionPurgesRewriteOnlyWhenNoRecordings() throws {
        let container = try Self.inMemoryContainer()
        let context = container.mainContext

        let expiredSession = RewriteSession(
            id: UUID(),
            createdAt: Self.eightDaysAgo(),
            flavor: "voice",
            selectionText: "old",
            instructionText: "old",
            output: "old",
            modelUsed: nil,
            title: "old"
        )
        context.insert(expiredSession)
        try context.save()

        let prior = UserDefaults.standard.object(forKey: "jot.retentionDays")
        defer {
            if let v = prior {
                UserDefaults.standard.set(v, forKey: "jot.retentionDays")
            } else {
                UserDefaults.standard.removeObject(forKey: "jot.retentionDays")
            }
        }
        UserDefaults.standard.set(7, forKey: "jot.retentionDays")
        let service = RetentionService(context: context)
        service.purgeOnce()

        let sessionsAfter = try context.fetch(FetchDescriptor<RewriteSession>())
        #expect(sessionsAfter.isEmpty)
    }

    // MARK: - Schema

    /// `RewriteSession` schema sanity: a row inserted into an in-memory
    /// container round-trips with all fields preserved. Catches a
    /// regression where `modelUsed: String?` were ever made non-optional.
    @Test func rewriteSessionRoundTrip() throws {
        let container = try Self.inMemoryContainer()
        let context = container.mainContext

        let id = UUID()
        let createdAt = Date()
        let session = RewriteSession(
            id: id,
            createdAt: createdAt,
            flavor: "fixed",
            selectionText: "hello",
            instructionText: "Rewrite this",
            output: "Hello.",
            modelUsed: "OpenAI · gpt-5.4-mini",
            title: "Hello."
        )
        context.insert(session)
        try context.save()

        let descriptor = FetchDescriptor<RewriteSession>(
            predicate: #Predicate { $0.id == id }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        let r = fetched[0]
        #expect(r.flavor == "fixed")
        #expect(r.selectionText == "hello")
        #expect(r.instructionText == "Rewrite this")
        #expect(r.output == "Hello.")
        #expect(r.modelUsed == "OpenAI · gpt-5.4-mini")
        #expect(r.title == "Hello.")
        #expect(r.modelUsedRowLabel == "OpenAI")
    }

    /// `modelUsed == nil` legacy / Apple-Intelligence-style rows must
    /// load cleanly; `modelUsedRowLabel` returns nil so the row UI
    /// hides the meta line.
    @Test func rewriteSessionWithNilModelUsedRoundTrips() throws {
        let container = try Self.inMemoryContainer()
        let context = container.mainContext

        let id = UUID()
        let session = RewriteSession(
            id: id,
            createdAt: .now,
            flavor: "voice",
            selectionText: "x",
            instructionText: "y",
            output: "z",
            modelUsed: nil,
            title: "z"
        )
        context.insert(session)
        try context.save()

        let descriptor = FetchDescriptor<RewriteSession>(
            predicate: #Predicate { $0.id == id }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].modelUsed == nil)
        #expect(fetched[0].modelUsedRowLabel == nil)
    }

    /// `defaultTitle(from:)` mirrors `Recording.defaultTitle` semantics:
    /// trimmed, capped at 40 chars with ellipsis, placeholder for empty.
    @Test func rewriteSessionDefaultTitleSemantics() {
        #expect(RewriteSession.defaultTitle(from: "") == "Untitled rewrite")
        #expect(RewriteSession.defaultTitle(from: "  short ") == "short")
        let long = String(repeating: "a", count: 80)
        let title = RewriteSession.defaultTitle(from: long)
        #expect(title.hasSuffix("…"))
        #expect(title.count <= 41)
    }

    // MARK: - Controller persistence policy
    //
    // Drive the harness fixed-flow Rewrite end-to-end and assert the
    // success path persists a `RewriteSession` row. The harness builds
    // its `JotComposition` with `useInMemoryModelStore: true` so this
    // test never touches the user's real `default.store`.

    @Test func rewriteControllerPersistsSessionOnSuccess() async throws {
        let harness = try await JotHarness(seed: .default)
        let unique = "PERSIST-\(UUID().uuidString)"
        let result = try await harness.rewrite(
            selection: "hello world",
            provider: .ollama(.respondsWith(unique))
        )
        #expect(result.pillError == nil)
        #expect(result.pastedText == unique)

        // Verify a row landed in the harness's in-memory ModelContext.
        let context = harness.services.modelContainer.mainContext
        let descriptor = FetchDescriptor<RewriteSession>()
        let sessions = try context.fetch(descriptor)
        #expect(sessions.count == 1)
        let row = try #require(sessions.first)
        #expect(row.flavor == "fixed")
        #expect(row.selectionText == "hello world")
        #expect(row.output == unique)
        // Plan §3 model-label rule: cloud/Ollama composes
        // "<displayName> · <effectiveModel>". The harness routes via
        // Ollama by default (see configureForRewrite), so the label
        // starts with the Ollama display name.
        let model = try #require(row.modelUsed)
        #expect(model.contains("Ollama"))
    }

    /// Plan §3 composition rule: Apple Intelligence stores `displayName`
    /// only — no SKU, no trailing dot. The harness's
    /// `StubAppleIntelligence` short-circuits the LLM call without
    /// touching the URL session, so this drives the Apple branch end-
    /// to-end with a canned response.
    @Test func rewriteAppleIntelligenceStoresDisplayNameOnly() async throws {
        let harness = try await JotHarness(seed: .default)

        let unique = "APPLE-\(UUID().uuidString)"
        await harness.stubAppleIntelligence.enqueueRewrite(unique)
        harness.services.llmConfiguration.provider = .appleIntelligence
        harness.stubPasteboard.simulatedExternalSelection = "hello"

        await harness.services.rewriteController.rewrite()
        try await JotHarness.awaitRewriteLeavesIdle(
            harness.services.rewriteController,
            timeout: .seconds(2)
        )
        try await harness.services.rewriteController.awaitTerminalState(timeout: .seconds(10))

        let context = harness.services.modelContainer.mainContext
        let sessions = try context.fetch(FetchDescriptor<RewriteSession>())
        #expect(sessions.count == 1)
        let row = try #require(sessions.first)
        let model = try #require(row.modelUsed)
        // Apple Intelligence rule: only displayName, no " · " separator.
        #expect(!model.contains(" · "))
        #expect(model.contains("Apple Intelligence"))
    }

    /// Voice flow (Rewrite with Voice) persists with `flavor == "voice"`
    /// and the spoken instruction transcript captured in
    /// `instructionText`. Verifies the second persist site in
    /// `RewriteController.runCustom`.
    @Test func rewriteWithVoicePersistsSession() async throws {
        let harness = try await JotHarness(seed: .default)
        let unique = "VOICE-\(UUID().uuidString)"
        // 1 second of silence — `StubTranscriber` returns canned text
        // regardless of audio content.
        let instruction = AudioSource.samples([Float](repeating: 0, count: 16_000))
        let result = try await harness.rewriteWithVoice(
            selection: "hello world",
            instruction: instruction,
            provider: .ollama(.respondsWith(unique))
        )
        #expect(result.pillError == nil)
        #expect(result.pastedText == unique)

        let context = harness.services.modelContainer.mainContext
        let sessions = try context.fetch(FetchDescriptor<RewriteSession>())
        #expect(sessions.count == 1)
        let row = try #require(sessions.first)
        #expect(row.flavor == "voice")
        #expect(row.selectionText == "hello world")
        #expect(row.output == unique)
        #expect(!row.instructionText.isEmpty)
    }

    /// LLM error path: provider responds 401, `runFixed`'s catch block
    /// fires, the run errors out, and **no `RewriteSession` row is
    /// persisted** — per plan §6 ("don't persist on error").
    @Test func rewriteDoesNotPersistOnLLMError() async throws {
        let harness = try await JotHarness(seed: .default)
        let result = try await harness.rewrite(
            selection: "hello world",
            provider: .ollama(.respondsWith401)
        )
        // The pill should reflect an error, no paste landed.
        #expect(result.pastedText == nil)

        let context = harness.services.modelContainer.mainContext
        let sessions = try context.fetch(FetchDescriptor<RewriteSession>())
        #expect(sessions.isEmpty)
    }

    /// Plan §6 critical: persist on LLM success **before** invoking
    /// `pasteReplacement(...)` — so a paste failure does NOT lose the
    /// row. Home becomes the recovery affordance for the rare paste-
    /// failure case. Drives the controller against a stub pasteboard
    /// configured to throw on synthetic ⌘V; afterwards the
    /// `RewriteSession` row must still be present.
    @Test func rewritePersistsEvenWhenPasteFailsAfterLLMSuccess() async throws {
        let harness = try await JotHarness(seed: .default)
        harness.stubPasteboard.simulatePasteVFailureOnce = true

        let unique = "PASTE-FAIL-\(UUID().uuidString)"
        let result = try await harness.rewrite(
            selection: "hello world",
            provider: .ollama(.respondsWith(unique))
        )
        // Paste failed → no paste lands in history.
        #expect(result.pastedText == nil)

        // But the row is persisted because persist runs BEFORE paste.
        let context = harness.services.modelContainer.mainContext
        let sessions = try context.fetch(FetchDescriptor<RewriteSession>())
        #expect(sessions.count == 1)
        let row = try #require(sessions.first)
        #expect(row.output == unique)
        #expect(row.flavor == "fixed")
    }

    /// Plan §6: an empty selection causes
    /// `RewriteController.captureSelection` to throw before reaching
    /// the LLM. No row should land because the LLM never produced an
    /// output.
    @Test func rewriteDoesNotPersistOnEmptySelection() async throws {
        let harness = try await JotHarness(seed: .default)
        let result = try await harness.rewrite(
            selection: "",
            provider: .ollama(.respondsWith("ignored"))
        )
        #expect(result.pastedText == nil)

        let context = harness.services.modelContainer.mainContext
        let sessions = try context.fetch(FetchDescriptor<RewriteSession>())
        #expect(sessions.isEmpty)
    }

    // MARK: - Privacy redaction corpus

    /// Plan §7: `RewriteSession.selectionText`, `instructionText`, and
    /// `output` participate in the redaction corpus that
    /// `LogScanner.fetchTranscripts()` (and `AboutPane`'s mirrored
    /// `recentTranscripts()`) feed into `PrivacyScanner`. With one row
    /// inserted into an in-memory context, all three fields >= 10 chars
    /// must surface in the corpus the scanner builds.
    @Test func rewriteFieldsParticipateInRedactionCorpus() async throws {
        let container = try Self.inMemoryContainer()
        let context = container.mainContext

        let session = RewriteSession(
            id: UUID(),
            createdAt: .now,
            flavor: "voice",
            selectionText: "the quick brown fox jumped over",   // 31 chars
            instructionText: "translate this to spanish",        // 25 chars
            output: "el rápido zorro marrón saltó",              // 28 chars
            modelUsed: "OpenAI · gpt-5.4-mini",
            title: "el rápido zorro marrón saltó"
        )
        context.insert(session)
        try context.save()

        // Replicate `LogScanner.fetchTranscripts()`'s corpus build —
        // we don't drive `LogScanner` directly because it depends on
        // a live `LLMConfiguration` graph. The query shape and the
        // count >= 10 gate are the load-bearing contract.
        var corpus: [String] = []
        var seen = Set<String>()
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast
        var descriptor = FetchDescriptor<RewriteSession>(
            predicate: #Predicate { $0.createdAt >= cutoff }
        )
        descriptor.fetchLimit = 2000
        for s in try context.fetch(descriptor) {
            for field in [s.selectionText, s.instructionText, s.output] {
                guard field.count >= 10 else { continue }
                guard seen.insert(field).inserted else { continue }
                corpus.append(field)
            }
        }
        #expect(corpus.contains("the quick brown fox jumped over"))
        #expect(corpus.contains("translate this to spanish"))
        #expect(corpus.contains("el rápido zorro marrón saltó"))
    }
}
