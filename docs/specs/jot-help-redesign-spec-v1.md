# Jot — Help Tab Redesign Spec v1

**Platform:** macOS 26.4+ only
**Framework:** SwiftUI (no HTML, no web views, no external UI libraries)
**Target:** The Help sidebar entry in Jot's main window
**Status:** Handoff spec for implementation agent

> This spec replaces the flat-grid Help tab with a hierarchy: hero concepts, sub-rows, and inline expansion. It precedes the chatbot spec v3 — chatbot grounding depends on the slug structure this doc defines.

---

## 1. What changes, what doesn't

### Changes
- **Basics tab** — redesigned around 3 hero concepts (Dictation, Cleanup, Articulate), each with sub-rows beneath.
- **Advanced tab** — reorganized into 4 sections (AI providers, System, Input, Sounds), each with tight card grids.
- **Troubleshooting tab** — layout unchanged; 3 new AI cards added to the existing grid.
- **All hero card descriptions** — audited to fit a 120-character budget.
- **Search behavior** — filters matching content; pauses animations during search.

### Doesn't change
- The sidebar structure, the tab order (Basics / Advanced / Troubleshooting), the search bar's location.
- Existing `info.circle` → Help deep-link contract from Settings.
- Existing components if suitable for reuse: `HelpSection`, `HelpSubsection`, `Callout`, `ExpandableRow`, `ShortcutChip`, `AnchorRail`.
- Liquid Glass behavior — automatic on sidebar/toolbar; content areas remain solid.

### Explicit non-goals
- No navigation changes (no new routes, no separate Help windows, no detail pages).
- No external graphics pipeline (Lottie, Rive, SVG assets) — all illustrations are native SwiftUI.
- No multi-column responsive reflow on Basics — heroes stack full-width regardless of window size.
- No per-row "favorite" / "pinning" — ornament, not value.

---

## 2. Information Architecture

### Basics — 3 heroes + sub-rows
```
Dictation                        ← hero card (animated)
├─ Toggle recording       ⌥Space ← sub-row (expandable)
├─ Push to talk           hold   ← sub-row (expandable)
├─ Cancel recording       esc    ← sub-row (expandable)
├─ Any-length recordings         ← sub-row (expandable)
├─ On-device transcription ANE   ← sub-row (expandable)
├─ Auto-transcribe               ← sub-row (PLAIN — no chevron)
├─ Re-transcribe                 ← sub-row (PLAIN — no chevron)
├─ Multilingual (25 langs)       ← sub-row (expandable — shows grid)
└─ Custom vocabulary             ← sub-row (expandable)

Cleanup                   optional ← hero card (animated)
├─ Choose a provider             ← sub-row (expandable)
├─ Editable prompt               ← sub-row (expandable)
├─ Graceful fallback on failure  ← sub-row (PLAIN)
└─ Raw + cleaned both saved      ← sub-row (PLAIN)

Articulate                optional ← hero card (animated)
├─ Articulate (Custom)    voice  ← sub-row (expandable)
├─ Articulate (Fixed)            ← sub-row (expandable)
├─ Intent classifier             ← sub-row (expandable)
└─ Shared invariants prompt      ← sub-row (PLAIN)
```

### Advanced — 4 sections
Each section = title + subtitle + 2-column card grid.
```
AI providers       → 6 cards: Apple Intelligence, OpenAI·Anthropic·Gemini,
                     Ollama, Custom base URL, Editable prompts, Test Connection

System             → 4 cards: Launch at login, Retention, Hide to tray,
                     Reset scopes

Input              → 4 cards: Input device, Custom vocabulary (cross-ref),
                     Bluetooth mic handling, Silent-capture detection

Sounds             → 3 cards: Recording chimes, Transcription complete,
                     Error chime
```

### Troubleshooting — flat grid, 11 cards
Existing 8 + 3 new AI cards:
```
Existing:
  Permissions · Modifier required · Bluetooth mic redirect ·
  Shortcut conflicts · Recording won't start? · Hotkey stopped working? ·
  Resetting Jot · Report an issue

New (AI-specific):
  AI unavailable · AI connection failed · Articulate giving bad results?
```

---

## 3. Component Architecture (SwiftUI)

### Top-level view tree
```swift
HelpView
├─ HelpSearchBar(text: Binding<String>, isSearching: Binding<Bool>)
├─ HelpTabPicker(selection: Binding<HelpTab>)   // Basics | Advanced | Troubleshooting
└─ switch selectedTab:
    ├─ HelpBasicsView
    │   └─ VStack(spacing: 8) {
    │       ForEach(heroes) { hero in
    │           HeroCard(hero: hero)
    │           SubRowList(rows: hero.subRows)
    │       }
    │   }
    ├─ HelpAdvancedView
    │   └─ VStack(spacing: 28) {
    │       ForEach(advancedSections) { section in
    │           AdvancedSectionView(section: section)
    │       }
    │   }
    └─ HelpTroubleshootingView
        └─ LazyVGrid(columns: 2) {
            ForEach(troubleshootingCards) { card in
                TroubleshootingCard(card: card)
            }
        }
```

### `HeroCard`
```swift
struct HeroCard: View {
    let hero: Hero
    @Environment(\.animationTimeline) var timeline
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(hero.title).font(.title2).fontWeight(.medium)
                if hero.isOptional {
                    Text("optional")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            Text(hero.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            HeroIllustration(kind: hero.illustrationKind)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            if let action = hero.conditionalAction, action.shouldShow() {
                Button(action.label) { action.perform() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

### `SubRowList` and `SubRow`
```swift
struct SubRowList: View {
    let rows: [SubRow]
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                SubRowView(row: row)
                if row.id != rows.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .padding(.leading, 14)          // space for the tree rule
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.5)
        }
        .padding(.bottom, 24)            // space before next hero
    }
}

struct SubRowView: View {
    let row: SubRow
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Row itself
            HStack(spacing: 8) {
                Text(row.name).font(.body)
                Spacer()
                if let chip = row.shortcutChip {
                    ShortcutChip(text: chip)
                }
                if row.isExpandable {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(duration: 0.25), value: isExpanded)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                guard row.isExpandable else { return }
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            }
            .background(isExpanded ? Color.primary.opacity(0.04) : Color.clear)
            
            // Expanded detail
            if isExpanded, let detail = row.detail {
                SubRowDetail(detail: detail)
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
    }
}
```

### `SubRowDetail`
Renders the four optional elements in order:
```swift
struct SubRowDetail: View {
    let detail: SubRowDetailContent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Prose (always present)
            Text(detail.prose)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // 2. Optional inline tip
            if let tip = detail.inlineTip {
                InlineTipView(tip: tip)
            }
            
            // 3. Optional warning callout (plain-bold, no colored box)
            if let warning = detail.warning {
                (Text("Watch out: ").fontWeight(.medium)
                    + Text(warning))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            // 4. Optional "Open in Settings →" link
            if let settingsLink = detail.settingsLink {
                Button {
                    settingsLink.action()
                } label: {
                    HStack(spacing: 4) {
                        Text(settingsLink.label)
                        Image(systemName: "arrow.right")
                    }
                    .font(.footnote)
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            
            // 5. Optional custom content (e.g., languages grid)
            if let custom = detail.customContent {
                custom
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background(Color.primary.opacity(0.04))
    }
}
```

### `InlineTipView` (the grey chip+text row)
```swift
HStack(spacing: 10) {
    ShortcutChip(text: tip.chip)            // monospace pill
    Text(tip.description)
        .font(.footnote)
        .foregroundStyle(.secondary)
}
.padding(.horizontal, 12)
.padding(.vertical, 10)
.background(Color(nsColor: .controlBackgroundColor))
.overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
.clipShape(RoundedRectangle(cornerRadius: 6))
```

### Data model
```swift
struct Hero: Identifiable {
    let id: String                              // slug: "dictation" | "cleanup" | "articulate"
    let title: String
    let subtitle: String                        // ≤120 chars
    let isOptional: Bool
    let illustrationKind: HeroIllustrationKind
    let subRows: [SubRow]
    let conditionalAction: ConditionalAction?
}

struct SubRow: Identifiable {
    let id: String                              // slug
    let name: String
    let shortcutChip: String?                   // nil for non-keyboard rows
    let isExpandable: Bool
    let detail: SubRowDetailContent?            // nil iff !isExpandable
}

struct SubRowDetailContent {
    let prose: String                           // 1–2 sentences, always present
    let inlineTip: InlineTip?
    let warning: String?
    let settingsLink: SettingsLink?
    let customContent: AnyView?                 // for special cases (languages grid)
}

enum HeroIllustrationKind {
    case dictation      // mic → waveform → text bubble
    case cleanup        // messy text → clean text (strikethrough dissolve)
    case articulate     // selection + instruction → rewrite
}

struct ConditionalAction {
    let label: String
    let shouldShow: () -> Bool
    let perform: () -> Void
}
```

---

## 4. Animated Illustrations — Level 1, Shared Timeline

### Shared timeline
All three hero illustrations read phase from a single `TimelineView` at the HelpView level. This guarantees they animate in lockstep — no one "dancing on its own" rhythm.

```swift
struct HelpBasicsView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = sharedPhase(date: context.date, loopSeconds: 6.0)
            VStack(spacing: 8) {
                ForEach(heroes) { hero in
                    HeroCard(hero: hero)
                        .environment(\.animationPhase, phase)
                    SubRowList(rows: hero.subRows)
                }
            }
        }
    }
    
    private func sharedPhase(date: Date, loopSeconds: Double) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return (t.truncatingRemainder(dividingBy: loopSeconds)) / loopSeconds
    }
}
```

### Reduce Motion fallback
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

// When reduceMotion is true, lock phase to 0.6 (a "resolved" keyframe).
let effectivePhase = reduceMotion ? 0.6 : phase
```

### Pause during search
When `isSearching == true`, freeze phase at the current value until search ends. Don't animate while the user is scanning — it's distracting.

```swift
let effectivePhase = isSearching ? frozenPhaseAtSearchStart : (reduceMotion ? 0.6 : phase)
```

### Illustration implementations

Each illustration is a SwiftUI `Canvas` or `HStack` composition using the phase to drive keyframes. No external assets.

**Dictation** (mic → waveform → text):
- Phase 0.0–0.3: mic icon fades in, fills slightly
- Phase 0.3–0.7: 7-bar waveform animates (each bar's height = sin(phase * 2π + barIndex * 0.2))
- Phase 0.7–1.0: text bubble fades in with "Hello world" + blinking caret
- Loop

**Cleanup** (messy → clean):
- Phase 0.0–0.4: "before" bubble visible with fillers rendered `.strikethrough()` + red strikethrough color
- Phase 0.4–0.7: "after" bubble opacity rises from 0 to 1 while before slides slightly left
- Phase 0.7–1.0: hold on resolved state
- Loop

**Articulate** (selection + instruction → rewrite):
- Phase 0.0–0.3: "before" text visible, selected fragment highlighted
- Phase 0.3–0.5: instruction bubble slides in from top ("make it formal")
- Phase 0.5–0.8: "after" text fades in (rewritten selection)
- Phase 0.8–1.0: hold
- Loop

### Tuning rules
- Loop duration: **6 seconds**. Fast enough to feel alive, slow enough to not demand attention.
- All eases: `.easeInOut`. Never linear, never bouncy.
- Never animate opacity below 0.2 for readability.
- A small "illustrative" label sits in the bottom-right corner of each illustration at `.caption2` + tertiary color, so users know it's a concept demo, not literal product output.

---

## 5. Content — hero titles, subtitles, sub-row bodies

### Hero budgets
| Field | Budget | Example |
|---|---|---|
| Hero title | ≤2 words | "Dictation" |
| Hero subtitle | **≤120 characters** | "Press the hotkey, speak, text appears where your cursor is." (60 chars) |
| Sub-row name | ≤4 words | "Toggle recording" |
| Sub-row detail prose | 1–2 sentences | "Press once to start, press again to stop and transcribe. Works in any app, in any field with focus." |

### Debug overlay
In `#if DEBUG`, overlay a 2px red outline on any Text that exceeds its budget, with the overflow count printed in the corner. Caught visually during development, never shipped.

```swift
#if DEBUG
struct BudgetOverflowModifier: ViewModifier {
    let maxChars: Int
    let actualChars: Int
    
    func body(content: Content) -> some View {
        content.overlay(
            actualChars > maxChars
                ? RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.red, lineWidth: 2)
                    .overlay(alignment: .topTrailing) {
                        Text("+\(actualChars - maxChars)")
                            .font(.caption2).foregroundStyle(.red)
                            .padding(2)
                    }
                : nil
        )
    }
}
#endif
```

### Build-time check
A Build Phase Swift script reads the hero/sub-row content catalog and fails the build if any field exceeds budget. Same pattern as the chatbot spec's `check-help-doc-budget.swift`.

### Copy-writing rules (for the 37-card audit)
1. **Outcome-first, mechanism-second.** "Start and stop dictation with one hotkey" not "Press to start, press again to stop."
2. **Kill hotkeys from descriptions.** The ShortcutChip says `⌥Space`; the description shouldn't repeat it.
3. **No "Use when you want…"** Users know when they want things.
4. **No tautology.** If the card is about Toggle Recording, don't say "the primary dictation hotkey."
5. **Plain English.** No "leverages," "utilizes," "powered by." "Runs on" is fine.

### Content catalog — Basics sub-row details

**Toggle recording** (expandable)
- Prose: "Press once to start, press again to stop and transcribe. Works in any app, in any field with focus."
- Inline tip: chip=`⌥Space`, desc="Default shortcut — rebind in Settings → Shortcuts"
- Settings link: "Open in Settings"

**Push to talk** (expandable)
- Prose: "Hold the shortcut to record, release to transcribe. Useful when you want precise control over when Jot is listening."
- Settings link: "Open in Settings"

**Cancel recording** (expandable)
- Prose: "Press Esc to discard without transcribing. Active only while recording so it doesn't steal Esc from other apps when you're not dictating."
- Warning: "Esc is hardcoded, not configurable. macOS global hotkeys must include a modifier — Esc is an exception reserved for canceling in-flight transformations."

**Any-length recordings** (expandable)
- Prose: "No hard time limit — dictate for as long as you need. Quality gradually diminishes for recordings longer than about an hour, so shorter sessions work best."

**On-device transcription** (expandable)
- Prose: "Parakeet TDT 0.6B v3 runs on the Apple Neural Engine via FluidAudio. Audio never leaves the Mac. The model downloads on first use, about 600 MB."

**Auto-transcribe** (PLAIN, no chevron)

**Re-transcribe** (PLAIN, no chevron)

**Multilingual (25 languages)** (expandable, custom content)
- Prose: "Parakeet auto-detects the language on each recording. Supported today:"
- Custom content: a `LazyVGrid` of 25 monospace language-code chips (EN, FR, DE, ES, IT, PT, NL, PL, RU, UK, SV, DA, FI, EL, CS, HU, RO, BG, HR, SK, SL, ET, LV, LT, MT).
- Closing line (below grid): "More languages will be added as Parakeet improves."

**Custom vocabulary** (expandable)
- Prose: "A short list of names, acronyms, or jargon Jot should prefer during transcription. Useful when 'Leena' keeps getting transcribed as 'Lena', or 'kubectl' becomes 'cube cuddle'."
- Warning: "Vocabulary entries override similar-sounding words. Adding many entries that sound alike causes unpredictable preference among them. Keep the list focused."
- Settings link: "Open in Settings"

**Choose a provider** (expandable)
- Prose: "Pick who does the AI work. Apple Intelligence is the default on macOS 26+ — on-device, private, free, but quality for Cleanup trails cloud models today. Cloud providers (OpenAI, Anthropic, Gemini) deliver strong results with your own API key. Ollama runs locally."
- Settings link: "Open in Settings"

**Editable prompt** (expandable)
- Prose: "The default cleanup prompt removes fillers, fixes grammar and punctuation, and preserves your voice. Power users can rewrite it; a reset-to-default restores the shipped version."
- Settings link: "Open in Settings"

**Graceful fallback on failure** (PLAIN)

**Raw + cleaned both saved** (PLAIN)

**Articulate (Custom)** (expandable)
- Prose: "Select any text, press the shortcut, speak an instruction like 'make this formal' or 'translate to Japanese' — the articulated text replaces your selection."
- Inline tip: chip=`voice`, desc="Voice-driven rewrite — unbound by default"
- Settings link: "Open in Settings"

**Articulate (Fixed)** (expandable)
- Prose: "Select text, press the shortcut, and Jot rewrites it with a fixed 'Articulate this' instruction. No voice step — useful when you just want a quick cleanup pass."
- Settings link: "Open in Settings"

**Intent classifier** (expandable)
- Prose: "A deterministic classifier routes each spoken instruction into one of four branches (voice-preserving, structural, translation, code) and picks a minimal tendency for the model. Your instruction stays the primary signal — the classifier just nudges the default."

**Shared invariants prompt** (PLAIN)

---

## 6. Advanced Tab

### Layout
```swift
struct HelpAdvancedView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(advancedSections) { section in
                AdvancedSectionView(section: section)
            }
        }
    }
}

struct AdvancedSectionView: View {
    let section: AdvancedSection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.headline).fontWeight(.medium)
                Text(section.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(section.cards) { card in
                    AdvancedCard(card: card)
                }
            }
        }
    }
}

struct AdvancedCard: View {
    let card: AdvancedCardData
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(card.title).font(.body).fontWeight(.medium)
                Spacer()
                Text(card.badge)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(card.body).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            // Expansion on click (same pattern as SubRow)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() } }
    }
}
```

### Section contents

**AI providers** (6 cards)
```
| Apple Intelligence    | default | On-device, private, free. Improving with each macOS release.    |
| OpenAI · Anthropic · Gemini | cloud | Best quality today. Bring your own API key.              |
| Ollama                | local   | Run any model locally. Bring your own hardware.                 |
| Custom base URL       | byo     | Route through your own endpoint. OpenAI-compatible APIs work.   |
| Editable prompts      | power   | Tune the Cleanup and Articulate system prompts. Reset available.|
| Test Connection       | diag    | Verify a provider works before turning Cleanup on.              |
```

**System** (4 cards)
```
| Launch at login       | on/off     | Start Jot automatically when you sign into your Mac.         |
| Retention             | 7 / 30 / 90| Auto-delete old recordings after N days. Or keep forever.    |
| Hide to tray          | default    | Closing the window keeps Jot running in the menu bar.        |
| Reset scopes          | 3 levels   | Settings only, all data, or permissions — tiered options.    |
```

**Input** (4 cards)
```
| Input device          | system | Follows the macOS Sound default. Per-device selection coming soon.|
| Custom vocabulary     | boost  | Names, acronyms, jargon. Override behavior — keep it focused.      |
| Bluetooth mic handling| auto   | Jot detects silent-capture redirects and surfaces a clear error.   |
| Silent-capture detection| safety | Zero-amplitude audio triggers a specific error, not an empty result.|
```

**Sounds** (3 cards)
```
| Recording chimes      | start / stop / cancel | Three distinct sounds for recording state changes.|
| Transcription complete| chime                 | A brief tone when the transcript lands at your cursor.|
| Error chime           | audible               | A distinct sound when something fails.            |
```

---

## 7. Troubleshooting Tab

Layout unchanged. Add 3 new cards to the existing grid. New cards use the same `TroubleshootingCard` component as existing ones.

### New cards

**AI unavailable**
- Badge: `apple-intelligence`
- Body: "Ask Jot and Cleanup require Apple Intelligence. Enable it in System Settings → Apple Intelligence, or switch to a cloud provider in Settings → AI."
- Illustration: a small SF Symbol composition (brain symbol + warning triangle)

**AI connection failed**
- Badge: `cloud`
- Body: "Your cloud provider isn't reachable. Check your API key in Settings → AI, confirm the model name is current, and use Test Connection to diagnose. For Ollama, make sure it's running locally."
- Illustration: cloud symbol with red slash

**Articulate giving bad results?**
- Badge: `prompt`
- Body: "If Articulate results feel off, the shared prompt may have been edited. Open Settings → AI → Customize prompt and choose Reset to default. Still bad? Try a different provider."
- Illustration: pencil + arrow-uturn symbol

---

## 8. Search

### Behavior
- **Filters**, not highlights. When the user types in the search bar, non-matching heroes, sub-rows, and Troubleshooting cards hide. The user sees only what matches.
- **Matches across all layers**: hero titles, hero subtitles, sub-row names, sub-row detail prose, Advanced card titles and bodies, Troubleshooting card titles and bodies.
- **Case-insensitive, substring match.** No fuzzy matching in v1 — keep it predictable.
- **Sub-row matches expand their hero** automatically so the user sees the row in context.
- **Animation pauses** — illustrations freeze at their current phase when `isSearching == true`. Resume when search clears.
- **Empty result state**: "No matches for '{query}'. Try a different term, or ask Ask Jot."

### Implementation
```swift
struct HelpSearchState {
    var query: String = ""
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    
    func matches(_ hero: Hero) -> Bool { /* substring match across all fields */ }
    func matches(_ subRow: SubRow) -> Bool { /* substring match */ }
    func matches(_ card: AdvancedCardData) -> Bool { /* substring match */ }
    func matches(_ card: TroubleshootingCardData) -> Bool { /* substring match */ }
}
```

Filtering is a computed view of the catalog, not a separate data path. When search clears, state returns to normal.

---

## 9. Accessibility

- **VoiceOver**: every hero, sub-row, and card has a clear `.accessibilityLabel`. Sub-row expanded state announced as "expanded" / "collapsed". Chevron rotation is purely visual — VoiceOver relies on the state announcement.
- **Reduce Motion**: illustrations freeze at a resolved keyframe (phase 0.6). No looping, no transitions.
- **Dynamic Type**: all text scales. Heroes use `.title2`, subtitles `.subheadline`, sub-row names `.body`, detail prose `.footnote`. Illustrations remain fixed at 140pt height (they're secondary content).
- **Keyboard navigation**: Tab cycles through heroes → sub-rows → Advanced cards → Troubleshooting cards. Return/Space toggles expansion on focused expandable rows.
- **Reduce Transparency**: hero and card backgrounds fall back from `.regularMaterial` to solid `Color(nsColor: .controlBackgroundColor)`.
- **Focus ring**: standard system focus ring on all interactive elements (use `.focusable()` + standard SwiftUI behavior — don't paint custom rings).

---

## 10. Testing

### Unit tests
1. `test_heroSubtitleBudget_under120Chars` — iterate all heroes, assert `subtitle.count <= 120`.
2. `test_subRowDetailBudget_under400Chars` — keep detail prose reasonable.
3. `test_plainRows_haveNoDetail` — rows marked `isExpandable == false` have nil detail.
4. `test_expandableRows_haveDetail` — rows marked `isExpandable == true` have non-nil detail.
5. `test_search_filtersAcrossAllLayers` — inject query, assert filtered catalog.
6. `test_search_expandsMatchingSubrow` — search for a sub-row, assert its hero is included.
7. `test_conditionalAction_hiddenWhenStateTrue` — e.g., "Set up AI →" hidden when AI already configured.

### UI tests
1. `test_basicsHasThreeHeroes`
2. `test_expandableRow_togglesOnClick`
3. `test_plainRow_doesNotRespondToClick`
4. `test_search_pausesAnimations`
5. `test_reduceMotion_freezesAnimations`
6. `test_advancedHasFourSections`
7. `test_troubleshootingHas11Cards`
8. `test_multilingualExpansion_shows25Languages`

### Manual smoke
- [ ] All heroes render with animated illustrations.
- [ ] Shared timeline — all three animations move in lockstep.
- [ ] Reduce Motion (System Settings → Accessibility → Display) freezes illustrations.
- [ ] Every expandable sub-row expands + collapses cleanly.
- [ ] Plain rows are visually distinct (no chevron, no hover highlight implying clickability).
- [ ] Search filters all three tabs.
- [ ] Search pauses animations.
- [ ] VoiceOver reads every element sensibly.
- [ ] Light + Dark + Tinted appearance modes all render correctly.
- [ ] Window resize: heroes stay full-width, sub-row text wraps cleanly, Advanced grid stays 2-column until window narrower than ~560pt (then 1-column).

---

## 11. Migration from current Help tab

### Audit process for the 37 current cards

For each existing card, classify:
1. **Promote to hero** — none; all 3 heroes are already identified.
2. **Keep as sub-row under a hero** — most Basics cards fall here.
3. **Move to Advanced** — configuration knobs (Launch at login, Retention, Sound chimes, etc.).
4. **Move to Troubleshooting** — symptom-based cards stay in Troubleshooting.
5. **Delete** — cards that describe features that no longer exist, or that are better covered by expansion of another row.

### Card-by-card mapping

**Basics tab (current) → new location:**
```
Toggle recording          → Dictation sub-row (expandable)
Push to talk              → Dictation sub-row (expandable)
Paste last transcription  → Advanced → System (not in Basics anymore)
Articulate (Custom)       → Articulate sub-row (expandable)
Articulate (fixed)        → Articulate sub-row (expandable)
On-device transcription   → Dictation sub-row (expandable)
Multilingual dictation    → Dictation sub-row (expandable, with grid)
Auto-correct              → Cleanup hero (renamed — see note below)
Cancel                    → Dictation sub-row (expandable)
Status pill               → Delete from Basics; mentioned in Dictation hero subtitle
Menu bar                  → Advanced → System
Copy last transcription   → Advanced → System
Keep clipboard            → Advanced → System (clipboard preservation card)
Recording library         → Delete from Basics (it's a sidebar entry, not a feature card)
Auto-Enter                → Advanced → System
```

Note: the current Basics tab uses the label "Auto-correct." For the redesigned tab, this becomes **Cleanup** as a hero. The word "Cleanup" maps cleanly to what the feature does (remove fillers, fix grammar) without claiming to "correct" anything the user said wrong.

**Advanced tab (current) → new location:**
```
LLM providers             → Advanced → AI providers (card)
Apple Intelligence        → Advanced → AI providers (card)
Ollama                    → Advanced → AI providers (card)
Endpoint and API key      → Advanced → AI providers (Custom base URL card)
Test Connection           → Advanced → AI providers (card)
Customize prompt          → Advanced → AI providers (Editable prompts card)
Sparkle updates           → DELETE (users don't care about the update mechanism)
Launch at login           → Advanced → System
Retention                 → Advanced → System
Setup Wizard              → DELETE from Help (it's a one-time flow, not reference material)
Sound feedback            → Advanced → Sounds section
Input device              → Advanced → Input section
Re-transcribe             → Dictation sub-row (PLAIN, no chevron)
```

**Troubleshooting tab:** existing 8 cards stay. Add 3 new AI cards.

### Copy audit for every retained card

For each card that survives migration, rewrite its description under the 120-char rule. This is the bulk of the content work. Budget ~1 sentence per card.

---

## 12. Implementation Order

1. **Skeleton** — `HelpView` + `HelpBasicsView` with 3 hard-coded heroes, static sub-rows, no expansion, no animation. Goal: render the shape.
2. **Sub-row expansion** — wire up `ExpandableRow` pattern, click-to-toggle, chevron rotation, detail area transitions.
3. **Hero illustrations, non-animated first** — draw the static "resolved" state of each illustration. Ensure they look right before adding motion.
4. **Shared TimelineView** — wire up the 6s phase, drive each illustration from the shared phase. Test on real hardware for frame drops.
5. **Reduce Motion support** — verify illustrations freeze correctly.
6. **Advanced tab** — section views + card grids. Reuse the expansion pattern from sub-rows.
7. **Troubleshooting tab** — add 3 new cards, confirm existing layout still renders correctly.
8. **Search** — filter logic + animation pause.
9. **Content audit** — rewrite all 37 current card descriptions under budget. This is a content task, not a code task.
10. **Debug overlay + build-time budget check** — prevents regression.
11. **Accessibility pass** — VoiceOver, Reduce Motion, Dynamic Type, keyboard nav.
12. **Unit + UI tests.**
13. **Manual smoke.**

Each step ends with a buildable app.

---

## 13. Out of Scope for v1 (v2 backlog)

- Per-user favorites / bookmarked sub-rows.
- Usage analytics (which sub-rows get expanded most).
- Video illustrations (Level 2/3 animations). Level 1 is enough.
- Search result ranking (v1 is substring match; no TF-IDF, no fuzzy).
- Inter-tab search (e.g., typing in Basics surfaces Advanced cards too). Each tab filters its own content.
- Deep linking from the chatbot's `ShowFeatureTool` — that lives in the chatbot spec and uses slug matching; this spec just has to ensure every referenced slug exists in the Feature registry.
- Fallback illustrations when illustration data is missing (every hero has one; don't over-engineer).
- A11y captions for illustrations beyond the "illustrative" label. The illustrations are decorative; content lives in text beside them.

---

## 14. Slugs used here, chatbot spec must reference

This redesign establishes the canonical slug set. The chatbot spec (v3) references these. When slugs change here, update `Feature.swift` and regenerate the chatbot's derived fragments.

**Hero slugs:** `dictation`, `cleanup`, `articulate`

**Dictation sub-row slugs:** `toggle-recording`, `push-to-talk`, `cancel-recording`, `any-length`, `on-device-transcription`, `auto-transcribe`, `re-transcribe`, `multilingual`, `custom-vocabulary`

**Cleanup sub-row slugs:** `cleanup-providers`, `cleanup-prompt`, `cleanup-fallback`, `cleanup-raw-preserved`

**Articulate sub-row slugs:** `articulate-custom`, `articulate-fixed`, `articulate-intent-classifier`, `articulate-shared-prompt`

**Advanced card slugs:** `ai-apple-intelligence`, `ai-cloud-providers`, `ai-ollama`, `ai-custom-base-url`, `ai-editable-prompts`, `ai-test-connection`, `sys-launch-at-login`, `sys-retention`, `sys-hide-to-tray`, `sys-reset-scopes`, `input-device`, `input-vocabulary` (alias of `custom-vocabulary`), `input-bluetooth`, `input-silent-capture`, `sound-recording-chimes`, `sound-transcription-complete`, `sound-error-chime`

**Troubleshooting slugs:** (8 existing) `permissions`, `modifier-required`, `bluetooth-redirect`, `shortcut-conflicts`, `recording-wont-start`, `hotkey-stopped-working`, `resetting-jot`, `report-issue`; (3 new) `ai-unavailable`, `ai-connection-failed`, `articulate-bad-results`

Total: ~40 slugs. Clean mapping from UI surface to slug to chatbot grounding doc reference.
