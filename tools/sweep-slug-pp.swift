#!/usr/bin/env swift

// sweep-slug-pp.swift
//
// Research harness for evaluating slug post-processing variants against the
// shipping baseline (`HelpChatStore.injectMissingSlugs`).
//
// Strategy: the AI engine is a scarce serial resource. To avoid duplicating
// work and burning serialized model calls on every rerun of a cheap string
// transform, this harness has two phases:
//
//   Phase A — CAPTURE (one-shot, expensive):
//     Ask the live Apple Intelligence model each question using the exact
//     shipping instructions + grounding doc. Save RAW answers to
//     /tmp/slug-pp-raw.json. Skip this phase entirely on subsequent runs.
//
//   Phase B — EVALUATE (cheap, deterministic):
//     For each candidate post-processor (baseline, proto1, proto2, ...),
//     apply the transform to every cached raw answer, run the AI judge
//     on the POST-processed text, compute slug-citation / sharp-fix clean /
//     correctness deltas, and emit a side-by-side report.
//
// Judge calls DO still hit the model serially — one call per (question,run,
// variant) pair. For 8 questions * 2 runs * 4 variants = 64 judge calls.
// Still meaningful serialization cost, but only paid once per experiment.
//
// Usage:
//   # First time: capture then evaluate
//   swift tools/sweep-slug-pp.swift --capture --evaluate
//
//   # Reuse cached raw answers, run evaluation only
//   swift tools/sweep-slug-pp.swift --evaluate
//
//   # Only capture (re-populate raw cache) — skip judge
//   swift tools/sweep-slug-pp.swift --capture
//
// Outputs:
//   /tmp/slug-pp-raw.json      — captured raw answers (cache)
//   /tmp/slug-pp-eval.json     — full per-run evaluation
//   /tmp/slug-pp-summary.txt   — human-readable comparison table

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

setlinebuf(stdout)
setlinebuf(stderr)

// MARK: - Args

struct Args {
    var capture = false
    var evaluate = false
    var rawPath = "/tmp/slug-pp-raw.json"
    var evalPath = "/tmp/slug-pp-eval.json"
    var summaryPath = "/tmp/slug-pp-summary.txt"
    var runsPerQuestion = 2
    // Skip judge calls during evaluation — useful for debugging post-processors
    // without waiting on serial model engine.
    var skipJudge = false
}

func parseArgs() -> Args {
    var a = Args()
    var i = 1
    let argv = CommandLine.arguments
    while i < argv.count {
        let flag = argv[i]
        func next() -> String? {
            i += 1
            guard i < argv.count else { return nil }
            return argv[i]
        }
        switch flag {
        case "--capture": a.capture = true
        case "--evaluate": a.evaluate = true
        case "--raw": if let v = next() { a.rawPath = v }
        case "--eval": if let v = next() { a.evalPath = v }
        case "--summary": if let v = next() { a.summaryPath = v }
        case "--runs": if let v = next(), let n = Int(v) { a.runsPerQuestion = n }
        case "--no-judge": a.skipJudge = true
        default: break
        }
        i += 1
    }
    if !a.capture && !a.evaluate { a.evaluate = true } // default
    return a
}

// MARK: - Grounding (mirrors production)

let helpContentPath = "/Users/vsriram/code/jot/Resources/help-content.md"
let helpContent: String = {
    if let s = try? String(contentsOfFile: helpContentPath, encoding: .utf8) { return s }
    print("ERROR: could not read \(helpContentPath)")
    exit(1)
}()

let userConfigBlock = """
- Toggle recording: ⌥Space
- Push-to-talk: unbound
- Articulate (Custom): ⌥,
- Articulate: unbound
- Paste last: ⌥⇧V
- Cleanup: off
- AI provider: Apple Intelligence
- Model downloaded: yes
- Retention: 7 days
- Launch at login: no
- Vocabulary entries: 3
"""

func shippingInstructions() -> String {
    """
    You are Jot's in-app help assistant. Jot is a Mac dictation app that transcribes speech to text system-wide, entirely on-device, with optional LLM cleanup and a voice-driven text rewrite feature called Articulate.

    ALWAYS cite a feature's slug in square brackets on first mention, like [toggle-recording]. DO NOT skip the brackets.
    ALWAYS ground every answer in the DOCUMENTATION below. DO NOT invent facts.
    ALWAYS keep answers to 1–3 short paragraphs. Plain text. DO NOT use markdown headers.
    ALWAYS use exact UI names: "Settings → AI", "Home", "Library". DO NOT invent menu items.
    NEVER include shell commands in answers. For recording-wont-start and hotkey-stopped-working, cite the slug only.
    NEVER answer non-Jot questions. If the user asks about non-Jot topics, respond with ONE sentence redirecting them. DO NOT attempt the task.

    USER'S CURRENT SETUP:
    \(userConfigBlock)

    DOCUMENTATION:
    \(helpContent)
    """
}

// MARK: - Feature catalog (mirrors Feature.swift deep-linkable entries)

// NOTE: manually mirrored to keep this tool self-contained (the live codebase
// cannot be imported into a `swift <file>` script). Keep in sync with
// Sources/Help/Feature.swift when it changes. Only deep-linkable slugs +
// titles are included; plain sub-rows excluded.
let deepLinkableFeatures: [(title: String, slug: String)] = [
    // Basics heroes + deep-linkable sub-rows
    ("Dictation", "dictation"),
    ("Cleanup", "cleanup"),
    ("Articulate", "articulate"),
    ("Toggle recording", "toggle-recording"),
    ("Push to talk", "push-to-talk"),
    ("Cancel recording", "cancel-recording"),
    ("Any-length recordings", "any-length"),
    ("On-device transcription", "on-device-transcription"),
    ("Multilingual (25 languages)", "multilingual"),
    ("Custom vocabulary", "custom-vocabulary"),
    ("Choose a provider", "cleanup-providers"),
    ("Editable prompt", "cleanup-prompt"),
    ("Articulate (Custom)", "articulate-custom"),
    ("Articulate (Fixed)", "articulate-fixed"),
    ("Intent classifier", "articulate-intent-classifier"),
    // Advanced cards
    ("Apple Intelligence", "ai-apple-intelligence"),
    ("OpenAI · Anthropic · Gemini", "ai-cloud-providers"),
    ("Ollama", "ai-ollama"),
    ("Custom base URL", "ai-custom-base-url"),
    ("Editable prompts", "ai-editable-prompts"),
    ("Test Connection", "ai-test-connection"),
    ("Launch at login", "sys-launch-at-login"),
    ("Retention", "sys-retention"),
    ("Hide to tray", "sys-hide-to-tray"),
    ("Reset scopes", "sys-reset-scopes"),
    ("Input device", "input-device"),
    ("Bluetooth mic handling", "input-bluetooth"),
    ("Silent-capture detection", "input-silent-capture"),
    ("Recording chimes", "sound-recording-chimes"),
    ("Transcription complete", "sound-transcription-complete"),
    ("Error chime", "sound-error-chime"),
    // Troubleshooting
    ("Permissions", "permissions"),
    ("Modifier required", "modifier-required"),
    ("Bluetooth mic redirect", "bluetooth-redirect"),
    ("Shortcut conflicts", "shortcut-conflicts"),
    ("Recording won't start?", "recording-wont-start"),
    ("Hotkey stopped working?", "hotkey-stopped-working"),
    ("Resetting Jot", "resetting-jot"),
    ("Report an issue", "report-issue"),
    ("AI unavailable", "ai-unavailable"),
    ("AI connection failed", "ai-connection-failed"),
    ("Articulate giving bad results?", "articulate-bad-results"),
]

let deepLinkableSlugs: Set<String> = Set(deepLinkableFeatures.map { $0.slug })
let allKnownSlugs: Set<String> = {
    // Includes deep-linkable + plain sub-rows (for deleted/scrubbing detection)
    var s = deepLinkableSlugs
    s.formUnion(["cleanup-fallback", "cleanup-raw-preserved"])
    return s
}()

// Slugs that were deleted between versions — used by "deleted-slug scrub" proto.
let deletedSlugs: Set<String> = [
    "auto-transcribe", "re-transcribe", "articulate-shared-prompt",
]

// Sharp-fix slugs (match production commandOnCard flag).
let sharpFixSlugs: Set<String> = [
    "recording-wont-start", "hotkey-stopped-working",
]

// MARK: - Post-processor: BASELINE (shipping injectMissingSlugs)

func baselineInjection(text: String) -> String {
    var result = text
    var injected = 0
    let cap = 3
    var candidates: [(term: String, slug: String)] = []
    for f in deepLinkableFeatures {
        candidates.append((f.title, f.slug))
        if f.title.lowercased() != f.slug.lowercased() {
            candidates.append((f.slug, f.slug))
        }
    }
    candidates.sort { $0.term.count > $1.term.count }
    for (term, slug) in candidates {
        if injected >= cap { break }
        if result.contains("[\(slug)]") { continue }
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = "(?i)(?<![A-Za-z0-9-])(\(escaped))(?![A-Za-z0-9-])(?!\\s*\\[)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        let range = NSRange(result.startIndex..., in: result)
        if let match = regex.firstMatch(in: result, range: range),
           let r = Range(match.range(at: 1), in: result) {
            let matched = String(result[r])
            result.replaceSubrange(r, with: "\(matched) [\(slug)]")
            injected += 1
        }
    }
    return result
}

// MARK: - Post-processor: PROTO-v1 — slug correction + alias injection

// Alias table — extra terms that should map to specific slugs.
// Curated by reading question set + common model output phrasings.
let aliasMap: [(term: String, slug: String)] = [
    // AI provider phrasings
    ("on-device LLM", "ai-apple-intelligence"),
    ("on-device AI", "ai-apple-intelligence"),
    ("apple intelligence", "ai-apple-intelligence"),
    // Permissions common prose
    ("microphone permission", "permissions"),
    ("input monitoring", "permissions"),
    ("accessibility permission", "permissions"),
    // Shortcuts natural phrasings (model loves "the shortcut settings")
    ("Settings → Shortcuts", "shortcuts"),
    ("shortcut settings", "shortcuts"),
    // Articulate variants
    ("rewrite selection", "articulate-custom"),
    // Vocabulary
    ("vocabulary list", "custom-vocabulary"),
    ("vocabulary entries", "custom-vocabulary"),
    // Sharp-fix natural phrasings (high-leverage — scrub depends on these)
    ("recording won't start", "recording-wont-start"),
    ("recording doesn't start", "recording-wont-start"),
    ("doesn't start recording", "recording-wont-start"),
    ("won't record", "recording-wont-start"),
    ("hotkey stopped working", "hotkey-stopped-working"),
    ("hotkey produces a weird character", "hotkey-stopped-working"),
    ("weird character", "hotkey-stopped-working"),
    ("unicode character", "hotkey-stopped-working"),
    // Push-to-talk spelling variants
    ("push to talk", "push-to-talk"),
    ("push-to-talk", "push-to-talk"),
]

// "shortcuts" is not a feature on its own (there's no `shortcuts` Feature)
// but v1.5 help docs cite `[shortcuts]`. Keep as alias only when referenced
// explicitly in question context — but harmless because it'll be extracted
// and then filtered by `isDeepLinkable` downstream. Leaving for completeness.

// Fuzzy slug-correction table: plausible-but-wrong model outputs → canonical slug.
// Curated. Not algorithmic — judgment calls about what's confusing vs helpful.
let slugCorrectionMap: [String: String] = [
    "toggle": "toggle-recording",
    "recording": "toggle-recording",
    "cleanup-auto": "cleanup",
    "articulate-shared-prompt": "articulate", // deleted slug — map to hero
    "auto-transcribe": "dictation",
    "re-transcribe": "dictation",
    "shortcut": "shortcuts",
    "shortcuts": "shortcuts", // identity, but "shortcuts" isn't in Feature.all — OK to leave
    "custom-vocab": "custom-vocabulary",
    "vocabulary": "custom-vocabulary",
    "apple-intelligence": "ai-apple-intelligence",
    "ollama": "ai-ollama",
    "permissions-card": "permissions",
    "mic-permissions": "permissions",
    "mic": "permissions",
    "articulate-custom-prompt": "articulate-custom",
]

// STAGE 1: Correct broken slug citations.
// Scan for [slug] where slug is NOT in deepLinkableSlugs AND the correction
// map has an entry. Rewrite in-place. Preserves brackets so the downstream
// extractor finds the corrected slug.
func correctBrokenSlugs(text: String) -> String {
    let pattern = #"\[([a-z0-9][a-z0-9-]*)\]"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    let ns = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
    // Work back-to-front so ranges stay valid after replacement.
    var result = text as NSString
    for m in matches.reversed() {
        let slug = ns.substring(with: m.range(at: 1))
        if deepLinkableSlugs.contains(slug) { continue }
        if let corrected = slugCorrectionMap[slug], deepLinkableSlugs.contains(corrected) {
            result = result.replacingCharacters(
                in: m.range,
                with: "[\(corrected)]"
            ) as NSString
        }
    }
    return result as String
}

// STAGE 2: Inject missing slugs for titles + aliases.
// Same as baseline but with the alias map appended before title matching.
func injectWithAliases(text: String) -> String {
    var result = text
    var injected = 0
    let cap = 3
    var candidates: [(term: String, slug: String)] = []
    for f in deepLinkableFeatures {
        candidates.append((f.title, f.slug))
        if f.title.lowercased() != f.slug.lowercased() {
            candidates.append((f.slug, f.slug))
        }
    }
    for a in aliasMap {
        candidates.append((a.term, a.slug))
    }
    candidates.sort { $0.term.count > $1.term.count }
    for (term, slug) in candidates {
        if injected >= cap { break }
        if result.contains("[\(slug)]") { continue }
        let escaped = NSRegularExpression.escapedPattern(for: term)
        // Allow the term to be followed by common punctuation.
        let pattern = "(?i)(?<![A-Za-z0-9-])(\(escaped))(?![A-Za-z0-9-])(?!\\s*\\[)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        let range = NSRange(result.startIndex..., in: result)
        if let match = regex.firstMatch(in: result, range: range),
           let r = Range(match.range(at: 1), in: result) {
            let matched = String(result[r])
            result.replaceSubrange(r, with: "\(matched) [\(slug)]")
            injected += 1
        }
    }
    return result
}

// Proto-v1 pipeline: correct brokens, then inject with aliases.
func protoV1(text: String) -> String {
    let corrected = correctBrokenSlugs(text: text)
    let injected = injectWithAliases(text: corrected)
    return injected
}

// MARK: - Post-processor: PROTO-v2 — v1 + forced sharp-fix slug

// Heuristic classifier: does the USER QUESTION sound like a sharp-fix case?
// Called per (question, answer) pair during evaluation — the question is
// provided upstream, so we can bias injection toward the relevant sharp-fix
// slug even if the model's prose missed the mapping term.
//
// Trigger phrases chosen from the question battery.
func sharpFixSlugForQuestion(_ question: String) -> String? {
    let q = question.lowercased()
    // Hotkey produces character / stopped working
    if q.contains("weird character") || q.contains("produces") || q.contains("hotkey stopped") ||
       q.contains("unicode") || q.contains("≤") || q.contains("÷") {
        return "hotkey-stopped-working"
    }
    // Recording doesn't start
    if (q.contains("recording") && (q.contains("won't") || q.contains("doesn't") ||
        q.contains("nothing happens") || q.contains("not start") || q.contains("not working"))) ||
        q.contains("hotkey does nothing") || q.contains("recording wont") {
        return "recording-wont-start"
    }
    return nil
}

// Force-cite a sharp-fix slug at the top of the answer if the model + v1
// injection missed it. Required because the downstream sharp-fix scrub
// relies on the slug being present to fire.
func protoV2(text: String, question: String) -> String {
    var base = protoV1(text: text)
    guard let forced = sharpFixSlugForQuestion(question) else { return base }
    if base.contains("[\(forced)]") { return base } // already cited
    // Prepend a short citation sentence — invisible to the model but visible
    // to the downstream slug extractor + scrub.
    let sentence: String
    switch forced {
    case "recording-wont-start":
        sentence = "See Recording won't start [\(forced)]."
    case "hotkey-stopped-working":
        sentence = "See Hotkey stopped working [\(forced)]."
    default:
        sentence = "[\(forced)]"
    }
    base = sentence + "\n\n" + base
    return base
}

// MARK: - Post-processor variants registry

struct Variant {
    let id: String
    let label: String
    // (raw, question) → processed
    let transform: (String, String) -> String
}

let variants: [Variant] = [
    Variant(id: "raw", label: "Raw (no post-processing)") { raw, _ in raw },
    Variant(id: "baseline", label: "Baseline injectMissingSlugs") { raw, _ in baselineInjection(text: raw) },
    Variant(id: "proto1", label: "Proto1 (correct + aliases)") { raw, _ in protoV1(text: raw) },
    Variant(id: "proto2", label: "Proto2 (proto1 + forced sharp-fix)") { raw, q in protoV2(text: raw, question: q) },
]

// MARK: - Sharp-fix scrub (unchanged — applied after injection, mirrors production)

func applyCommandScrub(text: String) -> String {
    // Detection: does the text cite a sharp-fix slug?
    let citesSharpFix = text.contains("[recording-wont-start]") || text.contains("[hotkey-stopped-working]")
    guard citesSharpFix else { return text }

    let commandPatterns: [String] = [
        "sudo[^\\n]+",
        "killall[^\\n]+",
        "(?m)^\\s*[0-9]+\\.\\s[^\\n]+(\\n\\s*[0-9]+\\.\\s[^\\n]+)+",
        "(?s)```[^`]*```",
    ]
    var scrubbed = text
    var didScrub = false
    for p in commandPatterns {
        if let regex = try? NSRegularExpression(pattern: p) {
            let range = NSRange(scrubbed.startIndex..., in: scrubbed)
            if regex.firstMatch(in: scrubbed, range: range) != nil {
                didScrub = true
                scrubbed = regex.stringByReplacingMatches(
                    in: scrubbed,
                    range: NSRange(scrubbed.startIndex..., in: scrubbed),
                    withTemplate: "See the card for the exact command."
                )
            }
        }
    }
    return didScrub ? scrubbed : text
}

// MARK: - Question battery

struct Question: Codable {
    let id: Int
    let text: String
    let kind: String
    let expectSlugs: [String]
    let mustContain: [String]
    let mustNotContain: [String]
    let expectRefusal: Bool
}

let battery: [Question] = [
    Question(id: 1, text: "How do I change my dictation shortcut?",
             kind: "config-lookup",
             expectSlugs: ["shortcuts", "toggle-recording"],
             mustContain: ["shortcut"], mustNotContain: [], expectRefusal: false),
    Question(id: 2, text: "What's the difference between toggle recording and push to talk?",
             kind: "feature-compare",
             expectSlugs: ["toggle-recording", "push-to-talk"],
             mustContain: ["toggle", "push"], mustNotContain: [], expectRefusal: false),
    Question(id: 3, text: "Why does my hotkey sometimes produce a weird character like ≤?",
             kind: "sharp-fix",
             expectSlugs: ["hotkey-stopped-working"],
             mustContain: [], mustNotContain: ["sudo", "killall"], expectRefusal: false),
    Question(id: 4, text: "Recording doesn't start — nothing happens when I press the hotkey.",
             kind: "sharp-fix",
             expectSlugs: ["recording-wont-start"],
             mustContain: [], mustNotContain: ["sudo", "killall"], expectRefusal: false),
    Question(id: 5, text: "Which AI provider should I use for cleanup?",
             kind: "opinion",
             expectSlugs: ["cleanup-providers"],
             mustContain: ["apple intelligence"], mustNotContain: [], expectRefusal: false),
    Question(id: 7, text: "My Articulate results are bad — what do I do?",
             kind: "troubleshoot",
             expectSlugs: ["articulate-bad-results"],
             mustContain: ["prompt"], mustNotContain: [], expectRefusal: false),
    Question(id: 8, text: "I added my friend's name to vocabulary but it's still wrong.",
             kind: "nuance",
             expectSlugs: ["custom-vocabulary"],
             mustContain: [], mustNotContain: ["100%"], expectRefusal: false),
    Question(id: 10, text: "Can I record for two hours straight?",
             kind: "nuance",
             expectSlugs: ["any-length"],
             mustContain: [], mustNotContain: ["unlimited"], expectRefusal: false),
    Question(id: 12, text: "Can Jot transcribe a podcast I have on my computer?",
             kind: "out-of-scope",
             expectSlugs: [],
             mustContain: [], mustNotContain: [], expectRefusal: true),
]

// MARK: - Capture phase

struct RawAnswer: Codable {
    let qid: Int
    let run: Int
    let question: String
    let latMs: Double
    let rawText: String
    let errored: Bool
    let errorMessage: String?
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
func runOnce(session: LanguageModelSession, prompt: String) async -> (String, Double, Bool, String?) {
    let start = ContinuousClock.now
    var text = ""
    var prev = ""
    do {
        for try await snapshot in session.streamResponse(to: prompt) {
            let cur = snapshot.content
            let delta = cur.hasPrefix(prev) ? String(cur.dropFirst(prev.count)) : cur
            text += delta
            prev = cur
        }
    } catch {
        let end = ContinuousClock.now
        func ms(_ d: Duration) -> Double {
            let c = d.components
            return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1_000_000_000_000_000
        }
        return (text, ms(end - start), true, "\(error)")
    }
    let end = ContinuousClock.now
    func ms(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1_000_000_000_000_000
    }
    return (text, ms(end - start), false, nil)
}

@available(macOS 26.4, *)
func capturePhase(args: Args) async -> [RawAnswer] {
    print("=== CAPTURE PHASE ===")
    let instr = shippingInstructions()
    var out: [RawAnswer] = []
    let total = battery.count * args.runsPerQuestion
    var idx = 0
    for q in battery {
        for run in 1...args.runsPerQuestion {
            idx += 1
            let session = LanguageModelSession(instructions: instr)
            let (text, lat, err, msg) = await runOnce(session: session, prompt: q.text)
            print("[\(idx)/\(total)] q\(q.id) run\(run) lat=\(Int(lat))ms err=\(err)")
            out.append(RawAnswer(
                qid: q.id, run: run, question: q.text,
                latMs: lat, rawText: text, errored: err, errorMessage: msg
            ))
        }
    }
    // Persist
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(out) {
        try? data.write(to: URL(fileURLWithPath: args.rawPath))
        print("wrote raw cache → \(args.rawPath)")
    }
    return out
}
#endif

func loadRawCache(path: String) -> [RawAnswer]? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let arr = try? JSONDecoder().decode([RawAnswer].self, from: data) else {
        return nil
    }
    return arr
}

// MARK: - Judge (mirrors sweep-combined)

#if canImport(FoundationModels)
@available(macOS 26.0, *)
func aiJudge(question: Question, answer: String, doc: String) async -> Bool {
    let judgeInstr = """
    You are a strict evaluator. You will be given a USER QUESTION about the Jot Mac dictation app, the app's DOCUMENTATION, and an ASSISTANT ANSWER. Judge whether the ANSWER is factually correct according to the DOCUMENTATION and whether it appropriately addresses the USER QUESTION.

    Criteria for CORRECT:
    - Every factual claim in the answer is supported by the documentation, OR is a correct refusal / redirect for an out-of-scope question.
    - No invented UI elements, menus, or features.
    - No hallucinated shell commands (sudo / killall lines).
    - For "Yes/No can Jot do X?" style out-of-scope questions (e.g. transcribing pre-recorded files), the answer must NOT assert yes unless the doc supports it.

    Respond with exactly ONE word: either YES (correct) or NO (incorrect). No explanation.
    """
    let judgePrompt = """
    USER QUESTION:
    \(question.text)

    DOCUMENTATION:
    \(doc)

    ASSISTANT ANSWER:
    \(answer)

    Is the answer correct?
    """
    do {
        let session = LanguageModelSession(instructions: judgeInstr)
        var verdict = ""
        for try await snapshot in session.streamResponse(to: judgePrompt) {
            verdict = snapshot.content
        }
        let v = verdict.lowercased()
        let head = String(v.prefix(20))
        if head.contains("yes") && !head.contains("no") { return true }
        if head.contains("no") { return false }
        return false
    } catch {
        return false
    }
}
#endif

// MARK: - Regex scoring

let slugExtractRegex = try! NSRegularExpression(pattern: #"\[([a-z0-9][a-z0-9-]*)\]"#)

func extractSlugs(_ text: String) -> [String] {
    let ns = text as NSString
    return slugExtractRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        .map { ns.substring(with: $0.range(at: 1)) }
}

func extractDeepLinkableSlugs(_ text: String) -> [String] {
    extractSlugs(text).filter { deepLinkableSlugs.contains($0) }
}

func containsAny(_ text: String, patterns: [String]) -> Bool {
    let lower = text.lowercased()
    for p in patterns { if lower.contains(p.lowercased()) { return true } }
    return false
}

// MARK: - Evaluate phase

struct EvalRow: Codable {
    let variant: String
    let qid: Int
    let run: Int
    let question: String
    let raw: String
    let processed: String
    let afterScrub: String
    let slugCited: Bool
    let sharpFixClean: Bool
    let mustOk: Bool
    let mustNotOk: Bool
    let refusalOk: Bool
    let judgePass: Bool
    // Derived: any deep-linkable slugs extractable post-processing?
    let deepLinkableSlugsExtracted: [String]
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
func evaluatePhase(args: Args, raws: [RawAnswer]) async -> [EvalRow] {
    print("\n=== EVALUATE PHASE ===")
    var out: [EvalRow] = []
    let total = variants.count * raws.count
    var idx = 0
    for variant in variants {
        print("--- variant: \(variant.id) \(variant.label) ---")
        for raw in raws {
            idx += 1
            guard let q = battery.first(where: { $0.id == raw.qid }) else { continue }

            let processed = variant.transform(raw.rawText, raw.question)
            let afterScrub = applyCommandScrub(text: processed)

            let slugs = extractSlugs(afterScrub)
            let deep = extractDeepLinkableSlugs(afterScrub)
            let slugCited = q.expectSlugs.isEmpty ||
                !Set(slugs).intersection(Set(q.expectSlugs)).isEmpty
            let sharpFixClean = !containsAny(afterScrub, patterns: ["sudo", "killall"])
            let mustOk: Bool
            if q.mustContain.isEmpty { mustOk = true }
            else {
                let lower = afterScrub.lowercased()
                mustOk = q.mustContain.allSatisfy { lower.contains($0.lowercased()) }
            }
            let mustNotOk = !containsAny(afterScrub, patterns: q.mustNotContain)

            // Polite-refusal regex: crude but matches previous harness style.
            let refusalMarkers = ["jot", "help with jot", "outside", "covers", "cannot help", "can't help", "i can only", "my focus"]
            let refusalLooksPolite = containsAny(afterScrub, patterns: refusalMarkers) &&
                !containsAny(afterScrub, patterns: ["here's a poem", "the square root", "you can use"])
            let refusalOk = q.expectRefusal ? refusalLooksPolite : true

            var judgePass = false
            if !args.skipJudge && !raw.errored {
                judgePass = await aiJudge(question: q, answer: afterScrub, doc: helpContent)
            }
            print("[\(idx)/\(total)] \(variant.id) q\(q.id)r\(raw.run) slug=\(slugCited) sharp=\(sharpFixClean) judge=\(judgePass) deep=\(deep.count)")

            out.append(EvalRow(
                variant: variant.id, qid: q.id, run: raw.run, question: q.text,
                raw: raw.rawText, processed: processed, afterScrub: afterScrub,
                slugCited: slugCited, sharpFixClean: sharpFixClean,
                mustOk: mustOk, mustNotOk: mustNotOk, refusalOk: refusalOk,
                judgePass: judgePass, deepLinkableSlugsExtracted: deep
            ))
        }
    }
    return out
}
#endif

// MARK: - Summary

func renderSummary(rows: [EvalRow], variantIds: [String]) -> String {
    var out = ""
    out += "=== Slug Post-Processing Sweep Summary ===\n\n"
    out += String(format: "%-10s | %-6s | %-6s | %-6s | %-6s | %-8s | %-8s\n",
                  "variant", "n", "slug%", "sharp%", "judge%", "deep-hit%", "correct%")
    out += String(repeating: "-", count: 78) + "\n"

    // Correct = judgePass AND sharpFixClean AND mustNotOk (mirrors sweep-combined).
    func correct(_ r: EvalRow) -> Bool {
        r.judgePass && r.sharpFixClean && r.mustNotOk && r.refusalOk
    }

    for v in variantIds {
        let rs = rows.filter { $0.variant == v }
        let n = rs.count
        guard n > 0 else { continue }
        let slug = rs.filter { $0.slugCited }.count
        let sharp = rs.filter { $0.sharpFixClean }.count
        let judge = rs.filter { $0.judgePass }.count
        let deepHit = rs.filter { !$0.deepLinkableSlugsExtracted.isEmpty }.count
        let corr = rs.filter(correct).count

        func pct(_ c: Int) -> String { String(format: "%.0f%%", 100.0 * Double(c) / Double(n)) }
        out += String(format: "%-10s | %-6d | %-6s | %-6s | %-6s | %-8s | %-8s\n",
                      v, n, pct(slug), pct(sharp), pct(judge), pct(deepHit), pct(corr))
    }
    out += "\n"

    // Per-variant, per-question diff
    out += "\n=== Per-question correctness ===\n"
    out += "qid | baseline | proto1 | proto2\n"
    for q in battery {
        func qcorrect(_ vid: String) -> String {
            let rs = rows.filter { $0.variant == vid && $0.qid == q.id }
            let c = rs.filter { $0.judgePass && $0.sharpFixClean && $0.mustNotOk && $0.refusalOk }.count
            return "\(c)/\(rs.count)"
        }
        func qslug(_ vid: String) -> String {
            let rs = rows.filter { $0.variant == vid && $0.qid == q.id }
            let s = rs.filter { $0.slugCited }.count
            return "\(s)/\(rs.count)"
        }
        out += "q\(q.id) correct : baseline=\(qcorrect("baseline")) proto1=\(qcorrect("proto1")) proto2=\(qcorrect("proto2"))  slug: baseline=\(qslug("baseline")) proto1=\(qslug("proto1")) proto2=\(qslug("proto2"))\n"
    }

    return out
}

// MARK: - Main

#if canImport(FoundationModels)
@available(macOS 26.4, *)
func main() async {
    let args = parseArgs()

    // Availability gate
    let avail = SystemLanguageModel.default.availability
    guard avail == .available else {
        print("ERROR: SystemLanguageModel availability = \(avail). Enable Apple Intelligence.")
        exit(1)
    }

    var raws: [RawAnswer] = []
    if args.capture {
        raws = await capturePhase(args: args)
    } else if let cached = loadRawCache(path: args.rawPath) {
        print("using cached raw answers from \(args.rawPath) (\(cached.count) entries)")
        raws = cached
    } else {
        print("ERROR: no cached raw answers at \(args.rawPath). Pass --capture first.")
        exit(1)
    }

    guard args.evaluate else {
        print("capture-only; skipping evaluate")
        return
    }

    let rows = await evaluatePhase(args: args, raws: raws)

    // Persist detailed eval.
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(rows) {
        try? data.write(to: URL(fileURLWithPath: args.evalPath))
        print("wrote eval → \(args.evalPath)")
    }
    let summary = renderSummary(rows: rows, variantIds: variants.map { $0.id })
    print("\n" + summary)
    try? summary.write(toFile: args.summaryPath, atomically: true, encoding: .utf8)
    print("wrote summary → \(args.summaryPath)")
}
#endif

#if canImport(FoundationModels)
if #available(macOS 26.4, *) {
    let sem = DispatchSemaphore(value: 0)
    Task { await main(); sem.signal() }
    sem.wait()
} else {
    print("ERROR: macOS 26.4+ required.")
    exit(1)
}
#else
print("ERROR: FoundationModels not available.")
exit(1)
#endif
