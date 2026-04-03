# OpenVoice — Cross-Platform Voice Dictation App

## Overview

A desktop app for voice dictation (Windows & macOS). Press a hotkey, speak, and transcribed text appears in whatever app you're using. Runs Whisper locally — no internet, no API keys, full privacy.

## Architecture

```
Electron App (Windows + macOS)
├── Main Process
│   ├── HotkeyManager (node-global-key-listener for keydown/keyup detection)
│   ├── HotkeyStateMachine (pure logic: PTT vs toggle mode)
│   ├── WhisperEngine (@anthropic-ai/whisper-node-addon or @nicepkg/whisper.cpp.wasm)
│   ├── AudioCapture (Web Audio API → Float32Array PCM)
│   ├── TextOutput (clipboard.writeText + robotjs Cmd+V/Ctrl+V)
│   ├── Dictionary (JSON word replacement, post-processing)
│   ├── Tray (system tray / menu bar icon + context menu)
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
| `@nicepkg/whisper.cpp.wasm` | Cross-platform Whisper (WASM, works on all platforms) |
| `node-global-key-listener` | Global keydown/keyup detection for PTT |
| `@hurdlegroup/robotjs` | Simulate paste into active window |
| `electron-store` | Persist settings and dictionary |
| `electron-builder` | Windows (NSIS) + macOS (DMG) installers |

**Note:** We use Web Audio API (via renderer process) for microphone capture — zero external dependencies.

## Platform Detection

```js
const isMac = process.platform === 'darwin';
const isWindows = process.platform === 'win32';
```

Key platform differences:

| Feature | Windows | macOS |
|---|---|---|
| Paste shortcut | `Ctrl+V` | `Cmd+V` |
| Default hotkey | `Ctrl+Shift+Space` | `Cmd+Shift+Space` |
| Hotkey modifier | `LEFT CTRL` | `LEFT META` |
| Model cache dir | `%APPDATA%/openvoice/models/` | `~/Library/Application Support/openvoice/models/` |
| Tray icon format | `.ico` | `.png` (template image) |
| Installer | NSIS `.exe` | DMG `.dmg` |

## Whisper Engine

**Primary: `whisper.cpp` via WASM** — Works on all platforms without native compilation.

For native performance on specific platforms:
- Windows/Linux: `@kutalia/whisper-node-addon` (requires MSVC/GCC)
- macOS: Native addon with Metal acceleration

The app auto-detects the best available engine at runtime.

### Default Model: `ggml-small.en.bin`

| Property | Value |
|---|---|
| GGML file | `ggml-small.en.bin` |
| Download URL | `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin` |
| Download size | 488 MB |
| RAM at runtime | ~1 GB |
| WER (English) | ~3% |
| Speed | ~3s for 10s audio |

Downloaded on first launch. Cached in platform-specific app data directory.

## Whisper API (WASM)

```typescript
import { createWhisper } from '@nicepkg/whisper.cpp.wasm';

const whisper = await createWhisper('/path/to/ggml-small.en.bin');

const result = await whisper.transcribe(audioFloat32Array, {
  language: 'en',
});

// Result: { text: string }
const text = result.text;
```

## Hotkey System

Single configurable hotkey. Platform-aware defaults:

| Platform | Default Hotkey |
|---|---|
| Windows | `Ctrl+Shift+Space` |
| macOS | `Cmd+Shift+Space` |

Two interaction modes detected by a state machine:

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
const modifierKey = isMac ? 'LEFT META' : 'LEFT CTRL';

listener.addListener((event, down) => {
  if (event.name === 'SPACE' && down[modifierKey] && down['LEFT SHIFT']) {
    if (event.state === 'DOWN') {
      stateMachine.keyDown();
    } else {
      stateMachine.keyUp();
    }
  }
});
```

**Note:** `node-global-key-listener` is currently archived/unmaintained but still functional. On macOS, requires Accessibility permissions.

## Audio Pipeline

1. Renderer process captures microphone via Web Audio API (`navigator.mediaDevices.getUserMedia`)
2. AudioWorklet processes raw PCM at 16kHz mono
3. PCM chunks sent to main process via IPC as Float32Array
4. On recording stop: accumulated Float32Array passed directly to Whisper

**No file I/O in the hot path. No WAV conversion. Direct PCM streaming.**

## Text Output Pipeline

Platform-aware paste:

```js
const isMac = process.platform === 'darwin';
const modifier = isMac ? 'command' : 'control';
robot.keyTap('v', modifier);
```

Full flow:
1. Save current clipboard contents
2. Write transcribed text to clipboard via `clipboard.writeText()`
3. Simulate paste via robotjs (Cmd+V on Mac, Ctrl+V on Windows)
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

Applied after transcription as word-boundary regex replacements (`\bkey\b` → value).

## System Tray / Menu Bar

App runs primarily in system tray (Windows) or menu bar (macOS).

| Platform | Icon Format | Notes |
|---|---|---|
| Windows | `.ico` | Standard system tray |
| macOS | `.png` | Template image (monochrome, ~18x18) |

Context menu:
- Recording status indicator
- Start/Stop recording
- Open settings
- Quit

## First-Launch Experience

1. Welcome screen with brief explanation
2. Request permissions (macOS: microphone + accessibility)
3. Download model (~488 MB, progress bar with resume support)
4. Set hotkey preference (platform default offered)
5. Test recording — speak a phrase, see it transcribed
6. App minimizes to tray/menu bar, ready to use

## Settings

| Setting | Windows Default | macOS Default |
|---|---|---|
| Hotkey | `Ctrl+Shift+Space` | `Cmd+Shift+Space` |
| Double-click threshold | 300ms | 300ms |
| Auto-paste | On | On |
| Clipboard restore delay | 150ms | 150ms |
| Start at login | Off | Off |
| Dictionary | `{}` | `{}` |

## Distribution

| Platform | Format | Notes |
|---|---|---|
| Windows | NSIS `.exe` | SmartScreen warning without code signing |
| macOS | DMG `.dmg` | Gatekeeper warning without notarization |

## Platform-Specific Gotchas

### Windows
1. **SmartScreen warning**: Add note in README about "More info" → "Run anyway"
2. **node-global-key-listener**: May need antivirus exceptions

### macOS
1. **Microphone permission**: System will prompt on first use
2. **Accessibility permission**: Required for global hotkeys and simulated keystrokes. App must guide user to System Preferences → Security & Privacy → Privacy → Accessibility
3. **Hardened Runtime**: For notarization, need to enable hardened runtime with entitlements
4. **node-global-key-listener**: Requires Accessibility permission to function
5. **Template icons**: Menu bar icons should be template images (monochrome)

## Out of Scope (v1)

- Real-time streaming transcription display
- Cloud API fallback
- Multi-language UI
- Auto-update mechanism
- Code signing / notarization
- Linux support
- Model selection UI
- Audio file transcription
