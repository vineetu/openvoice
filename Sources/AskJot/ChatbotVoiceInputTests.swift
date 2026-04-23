#if DEBUG
import Foundation

/// DEBUG-only runtime tests for `ChatbotVoiceInput`'s condensation skip
/// logic. Same pattern as `HelpInfraTests` — the shipping target has no
/// XCTest dependency, so invariants are asserted at launch.
///
/// Invoke `ChatbotVoiceInputTests.runAll()` from the debug-smoke path
/// once (e.g. alongside `HelpInfraTests.runAll()` in
/// `AppDelegate.applicationDidFinishLaunching`). These tests exercise
/// the pure-function surface of `ChatbotVoiceInput` (skip rules +
/// degenerate-output detection + condenser-race fallback) so they can
/// run in the app's main actor without touching the mic pipeline.
enum ChatbotVoiceInputTests {

    static func runAll() {
        testShouldSkipCondensation()
        testIsDegenerate()
        Task { await testRawFallbackOnCondenserFailure() }
        Task { await testRawFallbackOnTimeout() }
        Task { await testAcceptsValidCondensation() }
    }

    // MARK: - Skip conditions (spec v5 §8)

    static func testShouldSkipCondensation() {
        // < 15 words → skip.
        let shortInput = "how do I change my shortcut"
        assert(ChatbotVoiceInput.wordCount(shortInput) == 6)
        assert(ChatbotVoiceInput.shouldSkipCondensation(raw: shortInput),
               "short input under 15 words should bypass condensation")

        // Exactly at 15-word floor → still skipped (strict less-than).
        let fourteenWords = Array(repeating: "word", count: 14).joined(separator: " ")
        assert(ChatbotVoiceInput.wordCount(fourteenWords) == 14)
        assert(ChatbotVoiceInput.shouldSkipCondensation(raw: fourteenWords))

        // 15 words exactly → NOT skipped (threshold is "< 15").
        let fifteenWords = Array(repeating: "word", count: 15).joined(separator: " ")
        assert(ChatbotVoiceInput.wordCount(fifteenWords) == 15)
        assert(!ChatbotVoiceInput.shouldSkipCondensation(raw: fifteenWords))

        // > 300 words → skip.
        let longInput = Array(repeating: "word", count: 301).joined(separator: " ")
        assert(ChatbotVoiceInput.wordCount(longInput) == 301)
        assert(ChatbotVoiceInput.shouldSkipCondensation(raw: longInput),
               "long input > 300 words should bypass condensation")

        // Exactly 300 words → NOT skipped.
        let threeHundred = Array(repeating: "word", count: 300).joined(separator: " ")
        assert(!ChatbotVoiceInput.shouldSkipCondensation(raw: threeHundred))

        // Mid-range typical question → go.
        let normal = """
            um so I was wondering like how does Jot actually work behind the
            scenes when you press the hotkey and start speaking does it send
            anything to the cloud at all
            """
        assert(ChatbotVoiceInput.wordCount(normal) > 15)
        assert(ChatbotVoiceInput.wordCount(normal) < 300)
        assert(!ChatbotVoiceInput.shouldSkipCondensation(raw: normal))
    }

    // MARK: - Degenerate output detection

    static func testIsDegenerate() {
        let raw = """
            how does Jot actually transcribe my audio on my Mac without sending
            anything to the cloud
            """

        // Empty output → degenerate.
        assert(ChatbotVoiceInput.isDegenerate(condensed: "", raw: raw))
        assert(ChatbotVoiceInput.isDegenerate(condensed: "   ", raw: raw))

        // Under 30 % length ratio → degenerate.
        let tooShort = "OK."
        assert(Double(tooShort.count) / Double(raw.count) < 0.30)
        assert(ChatbotVoiceInput.isDegenerate(condensed: tooShort, raw: raw))

        // Refusal marker → degenerate.
        let refusal = "I cannot answer that question about the Jot application settings."
        assert(ChatbotVoiceInput.isDegenerate(condensed: refusal, raw: raw))

        let refusal2 = "I don't understand what you're asking about Jot's transcription."
        assert(ChatbotVoiceInput.isDegenerate(condensed: refusal2, raw: raw))

        // Good condensed output → not degenerate.
        let good = "How does Jot transcribe audio on-device without cloud access?"
        assert(Double(good.count) / Double(raw.count) >= 0.30)
        assert(!ChatbotVoiceInput.isDegenerate(condensed: good, raw: raw),
               "plausible single-sentence condensation should not be flagged")
    }

    // MARK: - Condenser race behavior

    static func testRawFallbackOnCondenserFailure() async {
        struct FailingCondenser: ChatbotCondenser {
            func condense(raw: String) async throws -> String {
                throw NSError(domain: "test", code: 1)
            }
        }
        let raw = "how does the cleanup feature remove filler words from my transcripts exactly"
        let result = await ChatbotVoiceInput.condenseIfEligible(
            raw: raw,
            condenser: FailingCondenser(),
            budget: .seconds(1)
        )
        assert(result == raw, "condenser failure must fall back to raw transcript")
    }

    static func testRawFallbackOnTimeout() async {
        struct SlowCondenser: ChatbotCondenser {
            func condense(raw: String) async throws -> String {
                try await Task.sleep(for: .seconds(5))
                return "should never reach this — timer wins"
            }
        }
        let raw = "what does the custom vocabulary setting actually do if I add a name"
        let start = ContinuousClock.now
        let result = await ChatbotVoiceInput.condenseIfEligible(
            raw: raw,
            condenser: SlowCondenser(),
            budget: .milliseconds(50)
        )
        let elapsed = ContinuousClock.now - start
        assert(result == raw, "timeout must fall back to raw transcript")
        assert(elapsed < .seconds(2), "timeout path should not wait for the slow condenser to finish")
    }

    static func testAcceptsValidCondensation() async {
        struct GoodCondenser: ChatbotCondenser {
            let output: String
            func condense(raw: String) async throws -> String { output }
        }
        let raw = """
            so I was wondering how does the multilingual transcription feature
            work does it auto-detect the language or do I have to pick one
            """
        let condensed = "How does Jot auto-detect the language for multilingual transcription?"
        let result = await ChatbotVoiceInput.condenseIfEligible(
            raw: raw,
            condenser: GoodCondenser(output: condensed),
            budget: .seconds(1)
        )
        assert(result == condensed, "a valid condensed output should be returned verbatim")
    }
}
#endif
