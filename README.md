# Jot

> Speak, and it's written.

Native macOS dictation utility. Press a hotkey, speak, and text appears at your cursor. Core transcription stays on-device; optional AI features can use Apple Intelligence, local Ollama, or configured cloud providers. No Jot account, no telemetry.

## Features

**Dictation** — Hit ⌥Space (or your custom shortcut), speak, and the transcript is pasted wherever your cursor is. Works in any app. Push-to-talk mode available too — hold the key, release to transcribe.

**Ask Jot** — A dedicated in-app chatbot for Jot help. Streaming, grounded in Jot's docs, on-device via Apple Intelligence by default, with optional OpenAI / Anthropic / Gemini / Ollama routing when you enable it. Includes voice input and clickable in-app feature links.

**AI Rewrite** — Select text, trigger the rewrite shortcut, and speak an instruction ("make this more formal", "fix the grammar", "translate to Spanish"). Jot sends the selected text + your voice instruction to an LLM, and the rewritten text replaces your selection. Supports Apple Intelligence, OpenAI, Anthropic, Gemini, and Ollama — configure the provider, endpoint, and API key in Settings. The prompts for both cleanup and rewrite are editable for power users, with a one-click reset.

**Transcript cleanup (optional)** — Opt in and every dictation gets a quick LLM pass to strip filler words ("um", "you know", false starts) and fix grammar while preserving your tone and meaning. Off by default; falls back to the raw transcript on any failure; runs against your configured provider (including local Ollama).

**Dynamic Island overlay** — A pill-shaped indicator appears under the notch showing recording state, transcription progress, and a preview of the result.

**Home + recordings** — Home now hosts the full recordings list: browse by date, search transcripts, play back audio, inspect detail, and manage saved recordings without a separate Library pane.

**Menu bar** — Start/stop recording, copy last transcript, check for updates, and open the main window from the menu bar icon. Jot ships as a single window with a sidebar for Home, Ask Jot, Settings, Help, and About — no separate Settings window.

**In-app discoverability** — Every Settings field carries an info popover with a "Learn more →" link that deep-jumps into the matching Help section, so you never have to leave the app to figure out what a toggle does.

**Sound cues** — Subtle chimes for recording start, stop, cancel, transcription complete, and errors. Configurable in Settings.

**Auto-update** — Jot checks for new releases daily via Sparkle and prompts to install signed updates. You can also trigger "Check for Updates…" manually from the app menu, menu bar, or About pane.

## Setup

On first launch, a setup wizard walks you through granting three macOS permissions (Microphone, Input Monitoring, Accessibility), downloading the Parakeet speech model (~1.2 GB, one-time), and configuring shortcuts.

If permissions get into a bad state, go to **Settings → General → Reset Permissions** or **Run Setup Wizard** to redo the flow.

To configure AI Rewrite or transcript cleanup, go to **Settings → AI**, pick your provider, and enter your API key (not needed for Ollama or Apple Intelligence). The cleanup toggle and prompt editor now live in **Settings → AI** alongside the provider configuration. Ask Jot uses Apple Intelligence by default; if you switch to a non-Apple provider, you can opt that provider into Ask Jot from the same pane. Press **Test Connection** any time you want to verify reachability — it's a manual diagnostic, not a gate.

## Stack

Swift · SwiftUI + AppKit · FluidAudio (Parakeet TDT 0.6B v3 on Apple Neural Engine) · AVAudioEngine · SwiftData · KeyboardShortcuts

## Requirements

- Apple Silicon Mac
- macOS Sonoma 14.0+

## References

- `docs/design-requirements.md` — product requirements
- `docs/features.md` — feature inventory

## Support

If Jot saves you time, you can [buy me a coffee ☕](https://ko-fi.com/vineetsriram).

## License

MIT — see [LICENSE](LICENSE).
