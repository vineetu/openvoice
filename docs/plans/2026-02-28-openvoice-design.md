# OpenVoice — Windows Voice Dictation App

## Overview

A Windows desktop app for voice dictation. Press a hotkey, speak, and transcribed text appears in whatever app you're using. Runs Whisper locally — no internet, no API keys, full privacy.

## Architecture

```
Electron App (Windows)
├── Main Process
│   ├── GlobalShortcut (hotkey detection + state machine)
│   ├── WhisperEngine (@kutalia/whisper-node-addon, model pre-loaded)
│   ├── AudioCapture (16kHz mono PCM via node-record-lpcm16)
│   ├── TextOutput (clipboard.writeText + robotjs Ctrl+V)
│   ├── Dictionary (JSON word replacement, post-processing)
│   ├── Tray (system tray icon + context menu)
│   └── electron-store (settings persistence)
└── Renderer Process (minimal UI)
    ├── Status indicator (idle / recording / transcribing)
    ├── Last transcription display
    ├── Dictionary editor
    └── Settings page
```

## Core Dependencies

| Package | Purpose |
|---|---|
| `electron` (v33+) | App shell |
| `@kutalia/whisper-node-addon` | Local Whisper inference with pre-loaded model |
| `@hurdlegroup/robotjs` | Simulate Ctrl+V to paste into active window |
| `node-record-lpcm16` | Microphone capture at 16kHz PCM |
| `electron-store` | Persist settings and dictionary |
| `electron-builder` + NSIS | Windows installer |

## Whisper Model

**Default model: `distil-large-v3.5`** (English-only)

| Property | Value |
|---|---|
| GGML file | `ggml-distil-large-v3.5.bin` |
| Download size | 1.52 GB |
| RAM at runtime | ~2 GB |
| WER (English) | ~2.5% |
| Speed (i7 CPU) | ~2s for 10s audio, 1.5x faster than large-v3-turbo |
| Source | `huggingface.co/distil-whisper/distil-large-v3.5` |

Downloaded on first launch. Cached in `%APPDATA%/openvoice/models/`.

## Hotkey System

Single configurable hotkey (default: `Ctrl+Shift+Space`). Two interaction modes detected by a state machine:

| Gesture | Behavior |
|---|---|
| **Hold** hotkey | Push-to-talk: recording starts on keydown, stops and transcribes on keyup |
| **Double-click** hotkey (two presses within 300ms) | Toggle mode: starts recording. Next single press stops and transcribes |

### State Machine

```
         hold keydown
  IDLE ─────────────────► RECORDING_PTT
   │                          │
   │ double-click             │ keyup
   │                          ▼
   │                    TRANSCRIBING ──► IDLE
   │
   ▼
  RECORDING_TOGGLE
   │
   │ single press
   ▼
  TRANSCRIBING ──► IDLE
```

Implementation uses `electron.globalShortcut` for registration. Keydown/keyup timing tracked via `node-global-key-listener` (non-blocking, so it doesn't steal the shortcut from other apps).

## Audio Pipeline

1. Microphone captured at 16kHz, mono, PCM 16-bit via `node-record-lpcm16`
2. PCM chunks streamed directly to `@kutalia/whisper-node-addon` (model already in memory)
3. On recording stop: final transcription returned as a string

No file I/O in the hot path. No WAV conversion. Direct PCM streaming.

## Text Output Pipeline

1. Save current clipboard contents
2. Write transcribed text to clipboard via `clipboard.writeText()`
3. Simulate `Ctrl+V` via `@hurdlegroup/robotjs` to paste into the active window
4. After 150ms delay, restore original clipboard contents

Fallback: if paste fails, text stays on clipboard for manual paste.

## Dictionary

A JSON map stored via `electron-store`:

```json
{
  "btw": "by the way",
  "addr": "123 Main Street",
  "openai": "OpenAI",
  "kubernetes": "Kubernetes"
}
```

Applied after transcription as word-boundary regex replacements (`\bkey\b` → value). Handles:
- Abbreviation expansion
- Proper noun capitalization (Whisper often lowercases names)
- Technical term correction
- Common misheard words

Editable via a simple UI: add/edit/delete entries in a table.

## System Tray

App runs primarily in the system tray (`.ico` icon). Context menu:
- Recording status indicator
- Start/Stop recording
- Open settings
- Quit

Main window is optional — can be shown/hidden from tray. Starts hidden after first setup.

## First-Launch Experience

1. Welcome screen with brief explanation
2. Download `distil-large-v3.5` model (1.52 GB, progress bar)
3. Set hotkey preference (default offered)
4. Test recording — speak a phrase, see it transcribed
5. App minimizes to tray, ready to use

## Settings

| Setting | Default | Notes |
|---|---|---|
| Hotkey | `Ctrl+Shift+Space` | User-configurable |
| Double-click threshold | 300ms | For toggle mode detection |
| Auto-paste | On | Toggle clipboard-only vs auto-paste |
| Clipboard restore delay | 150ms | Time before restoring original clipboard |
| Start with Windows | Off | Adds to registry Run keys via `auto-launch` |
| Dictionary | `{}` | User-editable JSON map |

## Distribution

- `electron-builder` with NSIS installer (standard Windows installer wizard)
- No code signing in v1 (users will see SmartScreen warning)
- Single `.exe` installer output
- Auto-installs MSVC++ runtime if missing

## Out of Scope (v1)

- Real-time streaming transcription display (we transcribe after recording stops)
- Cloud API fallback
- Multi-language support
- Auto-update mechanism
- Code signing / SmartScreen bypass
- macOS / Linux support
- Model selection UI (single model only)
- Audio file transcription (live microphone only)

## Known Windows Gotchas to Handle

1. **Microphone permission**: Check `systemPreferences.getMediaAccessStatus('microphone')` on startup. Show guidance if denied.
2. **Global hotkey conflicts**: Check `globalShortcut.register()` return value. Alert user if hotkey is taken.
3. **SmartScreen warning**: Add a note in README about "More info" → "Run anyway".
4. **Bluetooth mic selection**: Audio device can be wrong initially. Allow device selection in settings.
5. **Terminal paste**: Some terminals need `Ctrl+Shift+V` instead of `Ctrl+V`. Could detect in a future version.

## Windows Runtime Hardening (Task 15)

Critical issues discovered during audit that must be fixed before the app can run on Windows:

| Issue | Severity | Fix |
|---|---|---|
| `electron-store` v8+ is ESM-only; `require()` crashes | **CRASH** | Downgrade to v6.1.0 (last CJS version) |
| Native modules need rebuild for Electron ABI | **CRASH** | Add `postinstall: electron-builder install-app-deps` |
| Tray icon path breaks in packaged app | **CRASH** | Use `app.isPackaged` + `process.resourcesPath` |
| `node-record-lpcm16` requires SoX on PATH | **CRASH** | Bundle SoX binary or detect + show error |
| `startWithWindows` setting has no implementation | **Missing** | Use `app.setLoginItemSettings()` |
| No microphone permission check | **Missing** | Use `systemPreferences.getMediaAccessStatus()` |
| Test path assertions use Unix forward slashes | **Test fail** | Use `path.join()` in assertions |
| Hotkey conflict shows no user-facing error | **UX** | Surface to renderer via `setStatus()` |

See implementation plan Task 15 for detailed fix instructions.
