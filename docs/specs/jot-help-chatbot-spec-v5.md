# Jot — In-App Help Chatbot Spec v5

**Platform:** macOS 26.4+ only
**Framework:** SwiftUI + FoundationModels
**Target app:** Jot (menu-bar dictation app, single main window)
**Status:** Handoff spec for implementation agent. Supersedes v4.

> **Prerequisite:** The Help Tab Redesign Spec v1 must be implemented first. This spec grounds the chatbot against the Help tab's finalized 3-hero structure and ~40 canonical slugs defined in §14 of the Help redesign spec.

---

## 0. Changelog from v4

- **Chatbot placement moved from Home pane to dedicated sidebar entry.** The chatbot is no longer embedded in the bottom half of Home. It now lives as its own sidebar item called "Ask Jot", placed between Home and Library. The chatbot gets a full pane, full window height.
- **Home pane reverts to its original design** — banner + hint + Recent list only. No split, no chatbot region below.
- **Sparkle routing updated** — sparkle icons on Help hero cards and the About tab "Ask Jot" row now route to the Ask Jot sidebar entry, not Home.
- **Empty state scales up** — the same three starter prompts now fill a larger pane with more breathing room.
- **Availability-unavailable state applies to the whole pane**, not a sub-region.
- **State ownership unchanged** — `HelpChatStore` still lives at RootView level, conversation persists across sidebar navigation.

## Changelog from v3 (preserved for history)

- **Grounding doc restructured** around 3 concepts matching the Help tab heroes: Dictation, Cleanup, Articulate. No more "Recording + Transcription" split.
- **Slug registry replaced** by the Help redesign spec's §14 canonical list.
- **"Auto-correct" → "Cleanup"** throughout (matches Help tab hero name).
- **Deep-link targets clarified** — only expandable surfaces (hero cards, expandable sub-rows, Advanced cards, Troubleshooting cards) are valid tool targets. The 5 plain sub-rows (Auto-transcribe, Re-transcribe, Graceful fallback on failure, Raw + cleaned both saved, Shared invariants prompt) can be mentioned by name but not deep-linked.
- **Config deep-link preference** — when answering config questions, the bot surfaces the current value AND deep-links to the corresponding Advanced card or Settings pane.
- **Derivation pattern** simplified — fewer moving parts now that the slug registry lives in one place.

---

## 1. Scope & Non-Goals

### In scope
- Conversational help assistant answering questions about Jot, grounded in bundled documentation.
- **Dedicated sidebar entry "Ask Jot"** placed between Home and Library. Full-pane layout.
- Streaming responses, typewriter UX.
- Clear-and-restart button.
- Auto-reset on context-full errors with last-question prefill.
- Tool calling to deep-link into any expandable Help surface.
- Voice input using Jot's Parakeet ASR + Articulate pipeline for question condensation (10s budget).
- Sparkle icons on **3 Help tab heroes only** (Dictation, Cleanup, Articulate) — Basics tab only. All route to the Ask Jot sidebar pane.
- "Ask Jot" entry point on the About tab. Also routes to the sidebar pane.
- User's current Jot configuration injected into the system prompt.
- Advanced and Troubleshooting cards are valid deep-link targets.

### Explicit non-goals
- **No RAG.** Grounding doc ≤ 1500 tokens, stuffed into `instructions`.
- **No persistence across app launches.** Each launch = fresh state.
- **No multi-session management.** One conversation at a time.
- **No adapter / fine-tuning.**
- **No provider choice for the chatbot itself.** Always Apple Intelligence. Users configure cloud providers for Cleanup and Articulate, but the help assistant is product-owned infrastructure and must not cost API credits or depend on network.
- **No thinking/CoT.** Apple's model doesn't support it.
- **No embedding in Home, Help, or any other pane.** Ask Jot has its own sidebar entry; it doesn't share space.
- **No chatbot toolbar button.** Navigation is via sidebar only.
- **No deep-linking to plain (non-expandable) sub-rows.** The bot mentions them in prose but doesn't call ShowFeatureTool for them (clicking would land on a dead row).
- **No Articulate-based transcript compaction on context-full** — v1 just resets. v2 problem.

---

## 2. Dependencies & Availability

```swift
import FoundationModels
```

Observe `SystemLanguageModel.default.availability` on app launch AND throughout via `@Observable` tracking.

**The Ask Jot sidebar entry is always visible.** Availability only gates interactivity.

| Availability | Behavior |
|---|---|
| `.available` | Sidebar item fully interactive. Pane shows header, message area, input bar. Sparkle icons on 3 Basics heroes visible. "Ask Jot" row in About visible. |
| `.unavailable(anyReason)` | Sidebar item visible but muted (secondary color label). Pane header greyed, input non-interactive, message area shows a reason-specific one-liner + "Browse the Help tab →" link. Sparkle icons hidden (would link to a disabled chatbot). About "Ask Jot" row hidden. |

### Unavailability messages
- `.deviceNotEligible` — "Ask Jot needs an Apple Silicon Mac with Apple Intelligence. **Browse the Help tab →**"
- `.appleIntelligenceNotEnabled` — "Enable Apple Intelligence in System Settings to use Ask Jot. Or **browse the Help tab →**" (System Settings link via `x-apple.systempreferences:com.apple.preference.ai`)
- `.modelNotReady` — "Apple Intelligence is getting ready — this takes a few minutes on first run. Meanwhile, **browse the Help tab →**" (+ spinner)

Mid-session availability changes: in-flight stream cancels, prior messages stay readable, input disables until availability returns.

---

## 3. UX Placement — Dedicated Sidebar Entry

### Sidebar structure (top-to-bottom)
```
Home
Ask Jot                 ← new entry
Library
Help
Settings (bottom)
```

Icon: SF Symbol `sparkles`. Label: "Ask Jot". Place between Home and Library.

### Selected-state pane (full Detail width, full window height)
```
┌─────────────────────────────────────────────────┐
│  ✦  Ask Jot                          [Clear]    │  ← header
├─────────────────────────────────────────────────┤
│                                                 │
│                                                 │
│        Messages scroll here                     │
│        (or 3 starter prompts if empty)          │
│                                                 │
│                                                 │
│                                                 │
│                                                 │
├─────────────────────────────────────────────────┤
│  Ask about any feature…     🎙    ↑             │  ← input bar pinned to bottom
└─────────────────────────────────────────────────┘
```

### Why a sidebar entry and not Home-embedded
- Home is for "my transcripts" — the Recent list and quick-dictate hint. A chatbot region below fights Home's identity.
- The chatbot benefits from full window height — especially on 13" laptops where Home's split would squeeze both halves.
- Sidebar navigation is natural on macOS. Users find the entry, click, get the full experience.
- Deep-link destination is clean — sparkle tap on a Help hero just sets `sidebarSelection = .askJot`.

### Empty state (no messages yet)
Centered vertically in the pane. Three tappable starter prompts:
```
      How do I change my dictation shortcut?

      What's the difference between Cleanup and Articulate?

      Why won't a single key work as my hotkey?
```
Tap = fill TextField AND auto-send.

More breathing room than the Home-embedded v4 design. No cramped 240pt min-height anymore.

### Header row
- Leading: `sparkles` icon (accent-tinted) + "Ask Jot" title.
- Trailing: "Clear" button, visible only when `!messages.isEmpty`.

### Message area
- Vertically scrollable, fills all available space between header and input bar.
- Auto-scroll to bottom on new message.
- User messages: right-aligned, accent-tinted bubbles.
- Assistant messages: left-aligned, secondary-surface bubbles.

### Input bar (pinned to bottom)
- TextField with placeholder "Ask about any feature…"
- Trailing: inline mic button + send button. Wrap the button cluster in `GlassEffectContainer`.

### Sidebar badge on unread response (v2 backlog)
If the user navigates away mid-stream, a small unread dot could appear on the Ask Jot sidebar entry when the stream completes. Deferred; not in v1.

---

## 4. Architecture

```
┌───────────────────────────────────────────────────────┐
│ JotApp (@main)                                        │
│  └─ WindowGroup                                       │
│       └─ RootView                                     │
│            ├─ @State chatStore = HelpChatStore()   ← state owner (root level)
│            ├─ @State helpNavigator = HelpNavigator()
│            └─ NavigationSplitView                     │
│                 ├─ Sidebar: Home, Ask Jot, Library,   │
│                 │           Help, Settings            │
│                 └─ Detail: current pane               │
│                      ├─ HomeView                      │
│                      │    ├─ Banner                   │
│                      │    ├─ Dictate hint             │
│                      │    └─ RecentList               │
│                      ├─ AskJotView(store, nav)     ← full pane
│                      ├─ LibraryView                   │
│                      ├─ HelpView(nav)                 │
│                      └─ AboutView(nav)                │
└───────────────────────────────────────────────────────┘
```

### `HelpChatStore` (Observable, @MainActor)
- `messages: [ChatMessage]`
- `session: LanguageModelSession?` — recreated on `clear()` and on auto-reset.
- `state: ChatState` — `.idle | .streaming | .error(String) | .unavailable(Reason)`
- `availability: SystemLanguageModel.Availability`
- `userConfig: UserConfigSnapshot`
- `lastStreamTask: Task<Void, Never>?`
- `pendingPrefill: String?`

**Owned at RootView**, not AskJotView. Messages survive every sidebar navigation — user can click away to Home or Help and come back with their conversation intact.

### `HelpNavigator` (Observable)
Event bus coordinating cross-pane navigation:
- `sidebarSelection: SidebarItem?` — set to `.askJot`, `.help`, etc. to navigate.
- `switchHelpTab: HelpTab?` — Basics / Advanced / Troubleshooting, applied after `sidebarSelection = .help`.
- `highlightedFeatureId: String?` — auto-clears after 1.5s
- `pendingExpansion: String?` — ExpandableRow slug to open before scroll
- `focusChatInput: Bool` — focuses the Ask Jot pane's TextField after sidebar switch.
- `pendingPrefill: String?` — prefill text for the Ask Jot TextField.

Reused by:
- Existing Settings `info.circle` → Help deep-links (shipping; now update to use new slugs).
- Help card sparkle icon → Ask Jot sidebar pane (new).
- `ShowFeatureTool` → Help card (new, from chatbot).
- About tab "Ask Jot" row → Ask Jot sidebar pane (new).

### `UserConfigSnapshot` (injected into instructions)
```swift
struct UserConfigSnapshot {
    let toggleRecordingShortcut: String?       // e.g. "⌥Space" or nil
    let pushToTalkShortcut: String?
    let articulateCustomShortcut: String?
    let articulateFixedShortcut: String?
    let pasteLastShortcut: String?
    let cleanupEnabled: Bool
    let aiProvider: AIProvider?
    let modelDownloaded: Bool
    let retentionDays: Int                     // 7, 30, 90, or 0 for forever
    let launchAtLogin: Bool
    let vocabularyEntryCount: Int
}
```
Rebuilt on session create. Not re-injected per turn.

---

## 5. Documentation Strategy

### Compression target
Shipping `help-content.md` ≤ **1500 tokens**, measured via `SystemLanguageModel.default.tokenCount(for:)` at build time.

### Structure: 3 core concepts matching Help tab heroes

```markdown
# Jot

On-device Mac dictation. Hotkey → speak → transcript pastes at cursor.
Entirely local by default; cloud providers optional for Cleanup and Articulate.

## Dictation

Toggle [toggle-recording]: press hotkey (default ⌥Space) to start, press
again to stop and transcribe.

Push-to-talk [push-to-talk]: hold hotkey to record, release to stop.
Unbound by default.

Cancel [cancel-recording]: Esc discards without transcribing. Active only
while recording — never steals Esc when idle.

Any-length recordings [any-length]: no hard limit. Quality gradually
diminishes past ~1 hour; shorter sessions work best.

Transcription [on-device-transcription] runs on-device via Parakeet on
the Apple Neural Engine. Audio never leaves the Mac. Model downloads on
first use (~600 MB).

Multilingual [multilingual]: 25 European languages. Auto-detected per
recording.

Custom vocabulary [custom-vocabulary]: a short list of names, acronyms,
or jargon Jot should prefer. Overrides similar-sounding words — keep the
list focused; too many similar entries cause unpredictable preference.

## Cleanup (optional)

Off by default. An LLM polishes transcripts: removes fillers (um, uh,
like, you know), fixes grammar and punctuation, normalizes numbers
(e.g. "two thirty" → "2:30"), preserves the user's voice and word choice.

Providers [cleanup-providers]: Apple Intelligence runs on-device, private,
free — quality for Cleanup trails cloud today but improves with macOS.
Cloud providers (OpenAI, Anthropic, Gemini) use the user's API key —
typical heavy use costs ~$0.10–$0.40/month. Ollama runs locally with no
key needed.

Editable prompt [cleanup-prompt]: the default prompt is visible in
Settings → Transcription under "Customize prompt." Reset-to-default
available.

Fallback: if the LLM call fails or times out (10s), raw transcript is
delivered.

## Articulate (optional)

Rewrite selected text via a global shortcut. Two variants.

Articulate Custom [articulate-custom]: select text → hotkey → speak an
instruction ("make this formal", "translate to Japanese", "convert to
bulleted list") → result replaces selection. Unbound by default.

Articulate Fixed [articulate-fixed]: select text → hotkey → Jot rewrites
with a fixed "Articulate this" instruction. No voice step. Unbound by
default.

Intent classifier [articulate-intent-classifier]: routes each instruction
into one of four branches (voice-preserving, structural, translation,
code). The user's instruction is the primary signal; the branch picks a
minimal default tendency.

Both variants use the configured AI provider (same as Cleanup). Shared
prompt is editable in Settings → AI.

## Shortcuts

macOS requires global hotkeys to include a modifier (⌘ ⌥ ⌃ ⇧). Single-key
bindings are impossible [modifier-required]. If a hotkey produces a
Unicode character (≤, ÷), another app grabbed it while Jot was off — fix
is in Troubleshooting [hotkey-stopped-working].

All bindings live in Settings → Shortcuts [shortcuts]. Cancel (Esc) is
hardcoded.

## Paste & Clipboard

Auto-paste [auto-paste]: transcript pastes at cursor.
Auto-Enter [auto-enter]: press Return after paste. For chat inputs.
Clipboard preservation [clipboard-preservation]: original clipboard
restored after paste.
Copy last [copy-last]: ⌥⇧V re-pastes the most recent transcript.

## Troubleshooting highlights

- Permissions [permissions]: Mic, Input Monitoring, Accessibility.
- Bluetooth mic redirects [bluetooth-redirect]: Jot surfaces an actionable
  error instead of an empty transcript.
- Recording won't start [recording-wont-start]: coreaudiod fix on card.
- Hotkey produces Unicode character [hotkey-stopped-working]: re-register
  steps on card.
- AI unavailable [ai-unavailable] or connection failed [ai-connection-failed]:
  diagnostic guidance in Troubleshooting.
- Articulate giving bad results [articulate-bad-results]: reset prompt to
  default first.

## Privacy

Local-only by default: audio, transcripts, settings stay on the Mac. No
telemetry. Cloud providers only receive text if the user enables Cleanup
or Articulate with a cloud provider configured — their API key, their
provider. Only automatic network calls: one-time model download, daily
update check.
```

That's ~900 tokens of static prose. Derived fragments (below) add another ~150. User config injection adds ~80 tokens at session time. **Total: ~1130 tokens, leaving ~2400 for conversation** — more headroom than v3 had.

### Build-time derivation (§11 for details)
Some facts are derived from Swift enums so they can't drift:
- Cleanup pass count and names
- Articulate invariants and branch names
- Default shortcut bindings
- Retention default options
- Model name and size
- Supported language count and codes

### Provider guidance with concrete numbers
Must appear once in the doc (in the Cleanup section). Numbers are approximate, based on ~1500 words/day of dictation through Jot:
- Gemini Flash-Lite ~$0.10/month
- GPT-5 mini ~$0.13/month
- Claude Haiku ~$0.37/month

If pricing changes significantly, update the enum/fragment. Don't hand-edit.

### Expanded Troubleshooting — 11 surfaces
Matches Help redesign §7 exactly. All 11 are valid `ShowFeatureTool` targets. Two are marked `commandOnCard: true` (see §7 below).

### Deep-link targets: what the bot can route to
A slug is a valid ShowFeatureTool target if and only if its surface is expandable or is a standalone card. From the Help redesign §14:

**Expandable hero cards (3):** `dictation`, `cleanup`, `articulate`
**Expandable Dictation sub-rows (7 of 9):** `toggle-recording`, `push-to-talk`, `cancel-recording`, `any-length`, `on-device-transcription`, `multilingual`, `custom-vocabulary`
**Expandable Cleanup sub-rows (2 of 4):** `cleanup-providers`, `cleanup-prompt`
**Expandable Articulate sub-rows (3 of 4):** `articulate-custom`, `articulate-fixed`, `articulate-intent-classifier`
**Advanced cards (17):** all of them
**Troubleshooting cards (11):** all of them

**Plain sub-rows — NOT valid targets (5):**
- `auto-transcribe`, `re-transcribe`, `cleanup-fallback`, `cleanup-raw-preserved`, `articulate-shared-prompt`

The bot can still mention these by name in prose. The slug enum flags them with `isDeepLinkable: false` so the post-processing layer never calls ShowFeatureTool for them.

---

## 6. Prompt Design

### Instructions template
```swift
let instructions = """
You are Jot's in-app help assistant. Jot is a Mac dictation app that
transcribes speech to text system-wide, entirely on-device, with optional
LLM cleanup and a voice-driven text rewrite feature called Articulate.

ANSWER RULES:
- Ground every answer in the DOCUMENTATION below. If a question is
  outside scope, say so briefly and suggest what IS covered.
- Keep answers to 1–3 short paragraphs. Plain text, no markdown headers.
- When referring to a feature, append its slug in square brackets on
  first mention — e.g. "Toggle recording [toggle-recording] uses ⌥Space
  by default."
- Use exact UI names: "Settings → AI", "Home", "Library". Never invent
  menu items.
- For slugs marked commandOnCard (recording-wont-start,
  hotkey-stopped-working), do NOT include the command in your answer.
  Just cite the slug and let the user click through to the card.
- If the user asks about non-Jot topics, politely redirect.

USER'S CURRENT SETUP:
\(formattedUserConfig)

DOCUMENTATION:
\(helpContent)
"""
```

### `formattedUserConfig` shape (~80 tokens)
```
- Toggle recording: ⌥Space
- Push-to-talk: unbound
- Articulate (Custom): ⌥,
- Articulate: unbound
- Paste last: ⌥⇧V
- Cleanup: off
- AI provider: not configured
- Model downloaded: yes
- Retention: 7 days
- Launch at login: no
- Vocabulary entries: 3
```

### Session creation
```swift
let session = LanguageModelSession(
    instructions: instructions,
    tools: [ShowFeatureTool(navigator: helpNavigator)]
)

// Latency optimization: cache invariant prefix
let prefixPrompt = Prompt("\(userConfigBlock)\n\nAnswer:")
session.prewarm(promptPrefix: prefixPrompt)
```

Call `prewarm(promptPrefix:)` when the Ask Jot pane first becomes visible (user selects the sidebar entry) AND availability is `.available`. Do NOT prewarm on app launch — user may never visit the pane.

### Token budget
- Instructions framing: ~150 tokens
- User config: ~80 tokens
- Documentation: ~1130 tokens (prose + derived fragments)
- Tool schema (ShowFeatureTool with ~40-slug enum): ~220 tokens
- **Reserved for conversation: ~2500 tokens**
- Average turn: ~400 tokens → safe for ~6 turns before auto-reset territory

### Soft budget warning
At > 3500 tokens cumulative transcript: inline one-line "Conversation getting long — Clear to start fresh for best results." Non-blocking. Tapping "Clear" calls `clear()`.

---

## 7. Tool Calling — `ShowFeatureTool`

```swift
struct ShowFeatureTool: Tool {
    let navigator: HelpNavigator

    let name = "showFeature"
    let description = """
    Highlight a specific feature card in the Jot Help page. Call this when
    you mention a feature by its slug so the user can see the relevant
    surface.
    """

    @Generable
    struct Arguments {
        @Guide(description: "The feature slug from the documentation, in square brackets")
        let featureId: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        guard let feature = Feature.bySlug(arguments.featureId),
              feature.isDeepLinkable
        else {
            return ToolOutput("Feature not available")
        }
        await MainActor.run {
            navigator.switchTab = feature.tab          // .help (all paths go through Help)
            navigator.pendingExpansion = feature.expandableRowId
            navigator.highlightedFeatureId = feature.slug
        }
        return ToolOutput("Shown")
    }
}
```

### Two-phase deep-link (reuses existing info.circle pattern)
When the navigator switches to Help, it:
1. Switches the tab (Basics / Advanced / Troubleshooting) based on where the feature lives.
2. Expands the target row (for sub-rows) before scrolling.
3. Scrolls the target into view.
4. Pulses the card border with `accentColor.opacity(0.6)` for 1.5s, then fades.

This is the same code path as Settings `info.circle` → Help. Reuse, don't rebuild.

### Post-processing tool invocation
The model is instructed to cite slugs in square brackets in its text answer. After each assistant turn completes, a post-processing pass:

1. Extracts `[slug]` patterns from the final text.
2. Filters to only `isDeepLinkable == true` slugs.
3. Invokes ShowFeatureTool **once per unique slug, capped at 2 per turn**.
4. If 0 valid slugs are found, no tool call — the answer is pure text.

**Rationale:** small models are flaky at inline tool invocation. Post-processing from text is more reliable and avoids burning tokens on schema.

### Sharp-fix slug handling
Two slugs carry `commandOnCard: true`: `recording-wont-start` and `hotkey-stopped-working`. When the model's answer cites either:

1. Post-processing regex strips command-like content from the answer (patterns: `sudo …`, `killall …`, numbered step sequences). If regex matches anything, replace with "See the card for the exact command."
2. Invoke ShowFeatureTool normally.
3. The card is where the user reads the actual command in formatted monospace.

**Rationale:** users copying miswritten sudo commands from chat is a real risk. The card is the single source of truth.

---

## 8. Voice Input + Condensation

### Flow
```
[mic button tapped in TextField trailing edge]
   ↓
Jot's existing Parakeet ASR engine runs (shared pipeline)
   ↓
Status pill shows "Recording" with live waveform (existing pill, existing states)
   ↓
User taps mic again OR silence threshold → ASR completes
   ↓
Status pill shows "Transcribing" → "Condensing…"
   ↓
Raw transcript appears briefly in input field (visible to user)
   ↓
"Articulate condense" runs with Apple Intelligence (10s budget)
   ↓
Cleaned text REPLACES raw in TextField
   ↓
User confirms (Send / Return), OR auto-send after 2s idle
   ↓
Clean text → chatbot session
```

**Never auto-send raw without user confirmation.**

### Condensation reuses Articulate pipeline
Same code path as Articulate (Custom), new instruction:
```
Condense this spoken question about the Jot Mac app into a clear, single
sentence. Remove filler, self-corrections, and rambling. Preserve intent
exactly. Do not answer — just rewrite the question.

Spoken: "{raw}"
Condensed:
```

**Hardcoded to Apple Intelligence**, regardless of user's Articulate provider choice. Help is product-owned infrastructure.

### 10-second budget
Matches Jot's Cleanup pattern. Timeout → cancel → silently send raw. No error surfaced.

### Skip conditions (bypass condensation, send raw)
- Raw length < 15 words
- Raw length > 300 words
- Condensation output length < 30% of input
- Condensation output contains refusal markers ("I cannot", "I don't understand")
- Apple Intelligence unavailable

### Status pill reuse
Same Dynamic Island-style pill, same states: Recording → Transcribing → Condensing → (sent). No new in-chat indicators.

### Esc handling
Esc cancels: voice capture / condensation / in-flight stream. Scoped to chatbot-focused + active state. Consistent with Jot's global Esc contract (only during active transformations).

### Mic button states
- Idle: `mic.circle`, monochrome secondary
- Recording: `waveform.circle.fill`, animated, accent-tinted
- Condensing: `ellipsis.circle`, animated pulse
- Tap to start, tap to stop. No hold-to-talk (conflicts with global PTT).

### Voice-originated message attribution
Small muted `mic.fill` icon + "dictated" below the user bubble for messages that came through voice. No "cleaned with Articulate" label.

---

## 9. Sparkle Icon on 3 Basics Heroes

### Scope
Basics tab heroes only: Dictation, Cleanup, Articulate. Per the Help redesign, these are the 3 hero cards with animated illustrations. Sub-rows, Advanced cards, and Troubleshooting cards do NOT get sparkle icons — too noisy.

### Placement
Top-right of each hero card, flush with the "optional" label if present. SF Symbol `sparkles`, `.caption` size, secondary color. Hover: tint fills + tooltip "Ask Jot about this".

### Click behavior
1. `helpNavigator.sidebarSelection = .askJot`
2. `chatStore.pendingPrefill = contextualQuestion(for: slug)`
3. `helpNavigator.focusChatInput = true`
4. `AskJotView` observes the prefill, populates the TextField, and focuses it.
5. **Does not auto-send** — user reviews/edits, then sends.

### Contextual prefills
```swift
let prefills: [String: String] = [
    "dictation":  "How does Jot's dictation work end-to-end?",
    "cleanup":    "What does Cleanup do, and which provider should I pick?",
    "articulate": "What's the difference between Articulate Custom and Fixed?"
]
```
Single source of truth: `FeatureQuestionMap.swift`.

### Right-click context menu
On each of the 3 hero cards:
```swift
.contextMenu {
    Button("Ask Jot about this", systemImage: "sparkles") { … }
}
```

---

## 10. About Tab Integration

Add a row in About, placed above Support Jot:

```
✨  Ask Jot
    Ask about any feature in plain English.
    →
```

Tap → `navigator.sidebarSelection = .askJot` + `focusChatInput = true`. No prefill (context-free entry).

Hidden when Apple Intelligence unavailable.

---

## 11. Documentation Build Pipeline (Derivation)

### Files
```
Resources/
├── help-content-base.md          ← hand-written prose, checked into git
├── fragments/                    ← generated at build time, gitignored
│   ├── prompts.md
│   ├── shortcuts.md
│   ├── languages.md
│   ├── model-info.md
│   └── costs.md
└── help-content.md               ← concatenated final, gitignored

tools/
├── generate-fragments.swift            ← Build Phase step 1
├── concat-help-content.swift           ← Build Phase step 2
└── check-help-doc-budget.swift         ← Build Phase step 3 (fails build if > 1500 tokens)
```

### What gets derived
**Derived from Swift enums** (prevents drift):
- Cleanup pass count + names (from `CleanupPass.allCases`)
- Articulate shared invariants (from `ArticulateInvariant.allCases`)
- Articulate branch names (from `ArticulateBranch.allCases`)
- Default shortcut bindings (from `DefaultShortcuts` struct)
- Retention options (from `RetentionPeriod.allCases`)
- Model name + approximate size (from `TranscriptionModel` metadata)
- Supported language codes (from `SupportedLanguage.allCases`)
- Cost estimates per provider (from `ProviderCostEstimate` struct — editable one place if pricing shifts)

**Hardcoded in `help-content-base.md`:**
- The 3 core concept framings
- macOS version requirements
- Privacy posture
- UI pane names

### Source enums (hoist into Swift if not already)
```swift
enum CleanupPass: String, CaseIterable {
    case fillerRemoval = "filler removal"
    case grammarPunctCapitalization = "grammar and punctuation"
    case numberNormalization = "number normalization"
    case structurePreservation = "structure preservation"
    // keep in sync with prompt's rule list
}

enum ArticulateBranch: String, CaseIterable {
    case voicePreserving, structural, translation, code
}

enum ArticulateInvariant: String, CaseIterable {
    case selectionIsText = "selection is text, not instruction"
    case returnOnly = "return only the rewrite"
    case dontRefuse = "don't refuse on quality"
}

enum SupportedLanguage: String, CaseIterable {
    case en, fr, de, es, it, pt, nl, pl, ru, uk, sv, da, fi, el, cs, hu, ro, bg, hr, sk, sl, et, lv, lt, mt
}

struct ProviderCostEstimate {
    let provider: String
    let monthlyEstimate: String  // e.g. "~$0.10/month"
}
```

### Build phase ordering
1. `generate-fragments.swift` reads enums, writes markdown fragments.
2. `concat-help-content.swift` reads `help-content-base.md`, splices fragments into placeholder positions (e.g. `<!-- FRAGMENT: languages -->`), writes concatenated result.
3. `check-help-doc-budget.swift` loads the concatenated result, calls `tokenCount(for:)`, fails the build if > 1500.

If any step fails, the build fails. Shipping `.app` can never contain stale or over-budget doc.

### Why NOT include prompt text verbatim
Full Cleanup prompt ≈ 300 tokens. Articulate shared invariants + branch tendencies ≈ 400 tokens. Including verbatim would consume ~700 tokens for content the user can see/edit in Settings directly. Instead, describe *structure* (what passes exist, what invariants apply) and let ShowFeatureTool deep-link to the editable field.

---

## 12. Behavior — Clear, Cancel, Context-Full

### Clear button (header, trailing)
Visible only when `!messages.isEmpty`. No confirmation.
```swift
func clear() {
    lastStreamTask?.cancel()
    messages.removeAll()
    session = makeSession()
    session?.prewarm(promptPrefix: cachedPrefix)
    state = .idle
}
```

### Cancel in-flight stream (Esc)
Esc while chatbot focused + `state == .streaming` → cancel task, show partial with italic "(stopped)" suffix, state returns to `.idle`.

### Context-full auto-recovery
On `GenerationError.exceededContextWindowSize`:
1. Cancel stream.
2. Inline toast: "Chat was getting full — starting fresh. Your last question: '…'"
3. Auto-call `clear()`.
4. Prefill TextField with user's last question.
5. **Do NOT auto-resend.** User decides.

v2 will add Articulate-based transcript compaction (summarize old turns, preserve last 2). Deferred.

### Navigation mid-stream
Sidebar click while stream in flight → stream continues on the store in background. Return to Ask Jot → message is visible (complete or in-progress). State lives in store, not view.

---

## 13. Error Handling Matrix

### Foundation Models errors
| Case | Behavior |
|---|---|
| `.exceededContextWindowSize` | Auto-recovery per §12. |
| `.guardrailViolation` | "I can't help with that. Ask me about Jot's features." |
| `.unsupportedLanguage` | "I can only help in English right now." |
| Model unavailable mid-session | Observer transitions chatbot to disabled. In-flight stream cancels. Prior messages readable. When availability returns, input re-enables; existing conversation continues. |
| Stream delivers <5 tokens then dies | Replace partial with "Something went wrong. Try again." |
| Watchdog: no tokens in 10s | Cancel stream. Show "Taking too long — try again." |
| Tool called with unknown slug | Tool returns "Feature not available". Model rephrases. No crash. |
| Tool called with non-deep-linkable slug | Tool returns "Feature not available". Post-processing layer should have filtered this out; if it didn't, fail gracefully. |

### Voice + condensation
| Case | Behavior |
|---|---|
| Parakeet ASR fails / mic permission denied | Inline one-line: "Microphone not available. Check Settings → Privacy → Microphone." Mic button disabled. |
| ASR returns empty string | No-op. Subtle haptic. |
| Condensation fails / 10s timeout / nonsense | Silently send raw. |
| Mic tapped mid-condensation | Cancel in-flight, start new recording. Last one wins. |
| User types while mic recording | Stop recording, discard audio. Typing wins. |
| Global hotkey recording starts during chatbot mic | Chatbot mic cancels, discards in-progress capture. Global recording takes precedence. |
| Chatbot mic tapped during global recording | Chatbot mic disabled; no-op. Tooltip: "Finish your current recording first." |

### Input / UI
| Case | Behavior |
|---|---|
| Send while streaming | Button disabled; no-op. |
| Click Clear mid-stream | Cancel stream, clear, reinit. No confirmation. |
| Paste > 1000 tokens in TextField | Inline validator: "Message too long — try breaking it up." |
| Rapid double-click Send | Disabled state prevents; 500ms debounce backstop. |
| Window resized very short | Chatbot min height 240pt; below that, parent scrolls. |

### Document / build
| Case | Behavior |
|---|---|
| `help-content.md` missing at runtime | `fatalError` on launch — build pipeline broken, unshippable. |
| `help-content.md` > 1500 tokens | Build fails at budget check step. |
| Fragment placeholder unmatched | Build fails at concat step with clear error. |

### Privacy
| Case | Behavior |
|---|---|
| User pastes sensitive data | On-device, nothing leaves. No detection. |
| User asks bot to "remember my API key" | Context drops at session end. Footer: "Chat clears on close." |
| User config injection | Only local state — no secrets (no API keys, no clipboard, no transcripts). |

---

## 14. Accessibility

- VoiceOver on every message: "Assistant said: {content}" / "You asked: {content}".
- Streaming: update label only when `isPartial == false`.
- Send: Return key inside TextField.
- Clear: `⌘K` when chatbot focused.
- Mic: `⌘⇧M` when chatbot focused.
- Cancel stream: Esc when chatbot focused.
- Arrow keys navigate message history.
- Dynamic Type respected.
- All interactive elements have `.accessibilityLabel` and `.accessibilityHint`.

---

## 15. Testing

### Unit tests — `HelpChatStoreTests`
1. `test_clear_removesMessages`
2. `test_clear_createsFreshSession`
3. `test_storeOwnedAtRoot_survivesHomeRemount`
4. `test_contextFull_triggersAutoRecovery_withPrefill`
5. `test_tokenBudget_warnsAt3500`
6. `test_unavailable_disablesChatbot_showsReasonMessage`
7. `test_availabilityChange_midStream_cancelsStream_preservesMessages`
8. `test_condensation_fallsBackToRaw_onTimeout`
9. `test_condensation_skipsShortInputs`
10. `test_condensation_skipsLongInputs`
11. `test_condensation_skipsOnDegenerate`
12. `test_streamCancel_preservesPartial`
13. `test_userConfig_injectedIntoInstructions`
14. `test_esc_whileIdle_isNoOp`
15. `test_esc_whileStreaming_cancels`
16. `test_chatbotMic_disabled_whileGlobalRecordingActive`
17. `test_globalRecording_blocked_whileChatbotCapturing`
18. `test_toolCall_rejectsNonDeepLinkableSlug`
19. `test_toolCall_rejectsUnknownSlug`

### UI tests — `HelpChatUITests`
1. `test_sidebarHasAskJotBetweenHomeAndLibrary`
2. `test_askJot_persistsAcrossSidebarNavigation`
3. `test_sendButton_disabledWhileStreaming`
4. `test_clearButton_onlyVisibleWithMessages`
5. `test_sparkleOnHeroCard_navigatesToAskJotPaneWithPrefill`
6. `test_sparkleAbsentOnSubRows`
7. `test_aboutAskJot_navigatesToSidebarPane`
8. `test_micButton_cyclesStates`
9. `test_esc_whileChatFocused_cancelsStream`
10. `test_rightClickHeroCard_showsAskContextMenu`
11. `test_toolCall_switchesToCorrectTab_andHighlights`
12. `test_toolCall_expandsCollapsedRow_beforeScroll`
13. `test_unavailable_chatbotRegionDisabled_notHidden`
14. `test_unavailable_browseHelpLink_switchesToHelpTab`
15. `test_contextFull_autoRecoveryShowsPrefill`

### Golden-answer tests — `HelpChatGoldenTests`
File `tests/golden.json` (samples):
```json
[
  {
    "question": "How do I change my dictation shortcut?",
    "must_contain": ["Settings", "Shortcuts", "Toggle"],
    "must_not_contain": ["cannot", "not supported"]
  },
  {
    "question": "What's the difference between toggle recording and push to talk?",
    "must_contain": ["toggle-recording", "push-to-talk"]
  },
  {
    "question": "Why does my hotkey sometimes produce a weird character like ≤?",
    "must_contain": ["hotkey-stopped-working"],
    "must_not_contain": ["sudo", "killall"]
  },
  {
    "question": "Recording doesn't start — nothing happens when I press the hotkey.",
    "must_contain": ["recording-wont-start"],
    "must_not_contain": ["sudo killall coreaudiod"]
  },
  {
    "question": "Which AI provider should I use for cleanup?",
    "must_contain": ["Apple Intelligence", "privacy"]
  },
  {
    "question": "How much does cloud cleanup cost per month?",
    "must_contain": ["$"],
    "must_not_contain": ["expensive", "significant"]
  },
  {
    "question": "My Articulate results are bad — what do I do?",
    "must_contain": ["articulate-bad-results", "prompt"]
  },
  {
    "question": "I added my friend's name to vocabulary but it's still wrong.",
    "must_contain": ["custom-vocabulary"],
    "must_not_contain": ["guaranteed", "always correct"]
  },
  {
    "question": "What languages does Jot support?",
    "must_contain": ["multilingual"]
  },
  {
    "question": "Can I record for two hours straight?",
    "must_contain": ["any-length"],
    "must_not_contain": ["no limit", "unlimited"]
  },
  {
    "question": "What's my current dictation shortcut?",
    "must_contain": ["⌥Space"],
    "inject_config": { "toggleRecordingShortcut": "⌥Space" }
  }
]
```
Target: 30–40 pairs covering all 3 heroes, all 11 Troubleshooting slugs, provider questions, cost questions, vocabulary nuance, sharp-fix suppression, config injection.

### Manual smoke checklist
- [ ] M1, M3, M4 Macs.
- [ ] Apple Intelligence off → chatbot visible but disabled, reason message + Browse Help link work. Sparkles hidden. About row hidden.
- [ ] Apple Intelligence toggled off mid-session → region disables, stream cancels, prior messages remain readable.
- [ ] Apple Intelligence toggled back on → region re-enables, conversation continues.
- [ ] Reduce Transparency on → no broken rendering.
- [ ] Light + Dark + Tinted appearance modes.
- [ ] Navigate Ask Jot → Library → Ask Jot: messages persist.
- [ ] Navigate Ask Jot → Help → Home → Ask Jot: messages persist.
- [ ] Long messages wrap.
- [ ] Voice input quiet + noisy.
- [ ] Voice input rambling 5s → condensed correctly.
- [ ] Voice input clear 5s → condensation skipped, raw sent.
- [ ] Sparkle on each of 3 hero cards lands correctly with right prefill.
- [ ] Right-click "Ask Jot about this" on each hero.
- [ ] About → Ask Jot navigates to the Ask Jot sidebar pane + focuses input.
- [ ] Cancel mid-stream with Esc.
- [ ] Clear mid-stream.
- [ ] Context-full auto-recovery: force long conversation, verify prefill.
- [ ] Status pill shows correct states during voice input.
- [ ] Tool call to `toggle-recording` (expandable) → lands correctly.
- [ ] Tool call to `auto-transcribe` (plain) → gracefully skipped.
- [ ] Tool call to `recording-wont-start` → command stripped from answer, card opens.
- [ ] VoiceOver walkthrough of full conversation.

---

## 16. Source of Truth

### Files
- `Resources/help-content-base.md` — hand-written prose with `<!-- FRAGMENT: xxx -->` placeholders. Git.
- `Resources/fragments/*.md` — generated at build time. Gitignored.
- `Resources/help-content.md` — concatenated final. Gitignored.
- `Feature.swift` — slug registry with `isDeepLinkable`, `commandOnCard`, `tab`, `expandableRowId` metadata.

### Runtime load
```swift
guard let url = Bundle.main.url(forResource: "help-content", withExtension: "md"),
      let text = try? String(contentsOf: url, encoding: .utf8)
else { fatalError("help-content.md missing — build pipeline broken") }
```

Hard constraint: `tokenCount(for: text) <= 1500`.

### What each layer describes
- **37 Help tab surfaces** — the visual/UX product.
- **1500-token grounding doc** — the chatbot's textual reference.
- **Swift enums + Feature.swift** — the single source of truth for derivable values and slug metadata.

### When adding a new feature
1. Add the SwiftUI card/sub-row to the Help tab (per redesign spec).
2. Add the slug to `Feature.swift` with correct metadata.
3. Update `help-content-base.md` IF the feature is genuinely new (not a variant).
4. If the feature changes a derivable value (new cleanup pass, new language), update the Swift enum — doc regenerates automatically.
5. Add golden tests for likely questions.

All five steps in the same PR. Build fails if 1–4 are out of sync.

---

## 17. Known Gotchas

1. **FoundationModels 26.4 `@Generable` bug with long inputs** — not triggered here. Only `@Generable` usage is `ShowFeatureTool.Arguments` (single short string).
2. **4096-token ceiling** — instructions + user config + tool schema + transcript + output share it. Build-time doc check is the only thing standing between you and runtime explosions.
3. **No public tokenizer** — `tokenCount(for:)` is the only reliable measurement.
4. **`prewarm()` has latency cost** — call only when chatbot first becomes visible, not at app launch.
5. **`streamResponse` cannot overlap on a single session** — gate Send on `state == .idle`.
6. **Store ownership** — chatbot renders in AskJotView, but store MUST be owned by RootView. Correctness-critical — conversation must persist when user navigates to Home, Help, Library, or Settings and back.
7. **ExpandableRow deep-link is two-phase** — expand first, then scroll. Reuse existing info.circle code path.
8. **Availability observer** — AI can change at runtime. Subscribe, don't poll.
9. **User config injection is build-once-per-session** — don't re-inject per turn.
10. **Post-processing tool invocation** — model's text drives tool calls, not model's tool-invocation logic. More reliable for 3B models.
11. **Global recording vs. chatbot mic contention** — single-capture invariant enforced at engine layer, not UI.
12. **Plain sub-rows are not deep-linkable** — post-processing must filter these out before calling ShowFeatureTool.
13. **Sharp-fix slugs strip commands from answers** — regex-based scrub must run even if the model tried hard to include the command.

---

## 18. Build Order

1. Skeleton: `HelpChatStore`, `AskJotView`, new sidebar entry between Home and Library, wire into RootView's NavigationSplitView Detail pane. Hardcoded fake messages.
2. Replace fakes with real `LanguageModelSession.streamResponse`.
3. Availability observer + disabled-state UI.
4. Hoist required Swift enums (`CleanupPass`, `ArticulateBranch`, `ArticulateInvariant`, `SupportedLanguage`, `ProviderCostEstimate`, `DefaultShortcuts`, `RetentionPeriod`).
5. `help-content-base.md` drafted with `<!-- FRAGMENT: xxx -->` placeholders.
6. Build-phase scripts: fragment generator + concat + budget check.
7. `Feature.swift` slug registry (wait — this is already done by Help redesign spec. Reference it.)
8. User config injection.
9. Error handling matrix (§13).
10. Context-full auto-recovery (§12).
11. `ShowFeatureTool` + navigator integration with existing info.circle path.
12. Sparkle icon on 3 Basics heroes + right-click menu.
13. About tab "Ask Jot" row.
14. Voice input pipeline (reuse Parakeet + Articulate).
15. Status pill integration for chatbot voice states.
16. Liquid Glass styling pass.
17. Accessibility pass.
18. Unit + UI tests.
19. Golden-answer harness.
20. Manual smoke on real hardware.

Each step ends with a buildable app.

---

## 19. Out of Scope for v1 (v2 backlog)

- Articulate-based transcript compaction on context-full (v1 just resets).
- Persistent chat history across app launches.
- Inline citations to specific doc lines.
- Agentic tool calls ("open Settings → AI for me" as action, not highlight).
- Multi-language docs.
- iOS keyboard-extension integration (sandbox memory limits make it impossible).
- Embeddings-based retrieval (revisit only if docs exceed 3000 tokens).
- Regenerate-this-answer button.
- Thumbs up/down per-message feedback.
- Sparkle icons on Advanced or Troubleshooting cards.
- Multi-session / tabbed conversations.