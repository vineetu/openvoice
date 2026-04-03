# OpenVoice — Windows Voice Dictation App

## Overview

A Windows desktop app for voice dictation. Press a hotkey, speak, and transcribed text appears in whatever app you're using. Runs Whisper locally — no internet, no API keys, full privacy.

## Architecture

```
Electron App (Windows)
├── Main Process
│   ├── HotkeyManager (node-global-key-listener for keydown/keyup detection)
│   ├── HotkeyStateMachine (pure logic: PTT vs toggle mode)
│   ├── WhisperEngine (@kutalia/whisper-node-addon)
│   ├── AudioCapture (Web Audio API → Float32Array PCM)
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
| `@kutalia/whisper-node-addon` | Local Whisper inference (accepts Float32Array PCM directly) |
| `node-global-key-listener` | Global keydown/keyup detection for PTT |
| `@hurdlegroup/robotjs` | Simulate Ctrl+V to paste into active window |
| `electron-store` | Persist settings and dictionary |
| `electron-builder` + NSIS | Windows installer |

**Note:** We use Web Audio API (via renderer process) for microphone capture instead of `node-record-lpcm16` to avoid requiring users to install SoX.

## Whisper Model

**Default model: `distil-large-v3.5`** (English-optimized, multilingual base)

| Property | Value |
|---|---|
| GGML file | `ggml-model.bin` |
| Download URL | `https://huggingface.co/distil-whisper/distil-large-v3.5-ggml/resolve/main/ggml-model.bin` |
| Download size | 1.52 GB |
| RAM at runtime | ~2 GB |
| WER (English) | ~2.5% |
| Speed (i7 CPU) | ~2s for 10s audio |

Downloaded on first launch. Cached in `%APPDATA%/openvoice/models/`.

## Whisper API

The `@kutalia/whisper-node-addon` package has this API (verified from source):

```typescript
import whisper from '@kutalia/whisper-node-addon'

// Transcribe from Float32Array (preferred — no file I/O)
const result = await whisper.transcribe({
  pcmf32: audioFloat32Array,  // 16kHz mono Float32Array
  model: '/path/to/ggml-model.bin',
  language: 'en',
  use_gpu: true,
  no_timestamps: true,
});

// Result structure: { transcription: string[][] }
// Each segment is [startTime, endTime, text]
const text = result.transcription.map(seg => seg[2]).join(' ');
```

**Important:** There is no `init()` or `free()` method. The model path is passed to each `transcribe()` call. The addon handles model caching internally.

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

### Keyup Detection

Electron's `globalShortcut` only fires on keydown — it does not provide keyup events. For push-to-talk (PTT), we need keyup detection.

**Solution:** Use `node-global-key-listener` which provides both keydown and keyup events globally:

```typescript
import { GlobalKeyboardListener } from 'node-global-key-listener';

const listener = new GlobalKeyboardListener();
listener.addListener((event, down) => {
  if (event.name === 'SPACE' && down['LEFT CTRL'] && down['LEFT SHIFT']) {
    if (event.state === 'DOWN') {
      stateMachine.keyDown();
    } else {
      stateMachine.keyUp();
    }
  }
});
```

**Note:** `node-global-key-listener` is currently archived/unmaintained but still functional. Kutalia's electron-speech-to-speech uses it successfully. If stability issues arise, `iohook` is an alternative (requires node-gyp compilation).

## Audio Pipeline

1. Renderer process captures microphone via Web Audio API (`navigator.mediaDevices.getUserMedia`)
2. AudioWorklet processes raw PCM at 16kHz mono
3. PCM chunks sent to main process via IPC as Float32Array
4. On recording stop: accumulated Float32Array passed directly to `whisper.transcribe({ pcmf32 })`

**No file I/O in the hot path. No WAV conversion. Direct PCM streaming.**

### Why Web Audio API instead of node-record-lpcm16?

`node-record-lpcm16` requires SoX to be installed system-wide (`choco install sox.portable`). This adds friction for users and potential installation issues. Web Audio API is built into Chromium/Electron — zero dependencies.

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
2. Download model (1.52 GB, progress bar with resume support)
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
- Bundled with MSVC++ runtime

## Out of Scope (v1)

- Real-time streaming transcription display (we transcribe after recording stops)
- Cloud API fallback
- Multi-language support (model supports it, but UI doesn't expose it)
- Auto-update mechanism
- Code signing / SmartScreen bypass
- macOS / Linux support
- Model selection UI (single model only)
- Audio file transcription (live microphone only)

## Known Windows Gotchas to Handle

1. **Microphone permission**: Check `systemPreferences.getMediaAccessStatus('microphone')` on startup. Show guidance if denied.
2. **Global hotkey conflicts**: Test hotkey registration on startup. Alert user if hotkey is taken.
3. **SmartScreen warning**: Add a note in README about "More info" → "Run anyway".
4. **Bluetooth mic selection**: Audio device can be wrong initially. Allow device selection in settings.
5. **Terminal paste**: Some terminals need `Ctrl+Shift+V` instead of `Ctrl+V`. Could detect in a future version.
6. **node-global-key-listener permissions**: On some systems, the key listener may need admin privileges or antivirus exceptions.
