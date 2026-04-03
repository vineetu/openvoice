# OpenVoice

Cross-platform voice dictation app (macOS & Windows). Press a hotkey, speak, and transcribed text appears in whatever app you're using. Runs Whisper locally — no internet, no API keys, full privacy.

## Install

### macOS

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the DMG and drag OpenVoice to Applications
3. First launch: right-click → Open (Gatekeeper warning since app isn't notarized)
4. Grant **Microphone** permission when prompted
5. Grant **Accessibility** permission: System Preferences → Security & Privacy → Privacy → Accessibility → add OpenVoice

### Windows

1. Download the latest `.exe` installer from [Releases](../../releases)
2. Run the installer
3. If SmartScreen appears, click **More info** → **Run anyway** (app isn't code-signed yet)

## First Launch

On first launch the app will:
1. Open the main window and download the Whisper speech model (~488 MB). Progress bar shows status.
2. Load the model into memory (takes a few seconds).
3. Minimize to the **menu bar** (macOS) or **system tray** (Windows) once ready.

No internet connection is needed after the model is downloaded.

## Usage

| Platform | Hotkey | Action |
|----------|--------|--------|
| macOS | **Cmd+Shift+Space** | Hold to record, release to transcribe |
| Windows | **Ctrl+Shift+Space** | Hold to record, release to transcribe |

Or double-tap the hotkey to toggle recording on/off.

Transcribed text is copied to the clipboard and auto-pasted into whatever app has focus.

### Menu bar / Tray icon

Right-click the icon to:
- **Show Window** — open the main UI
- **Start / Stop Recording** — same as the hotkey
- **Quit** — fully exit the app

### Closing vs quitting

Clicking the window **X** button hides the app to the menu bar/tray (it keeps running). To fully quit, use **Quit** from the menu.

## Features

- **Push-to-talk** — Hold hotkey to record, release to transcribe
- **Toggle mode** — Double-tap hotkey to start, single tap to stop
- **Dictionary** — Add custom word replacements for words Whisper gets wrong
- **Auto-paste** — Transcribed text is automatically pasted into the active app
- **System tray / Menu bar** — Runs in the background, always one hotkey away
- **Offline** — Everything runs locally, no internet required after model download

## Development

Requires Node.js 20+.

```bash
npm install
npm test        # run unit tests
npm start       # launch in dev mode
```

Build installers:

```bash
npm run build:mac   # creates dist/*.dmg
npm run build:win   # creates dist/*.exe (requires Windows)
```

Native addons may need rebuilding:
```bash
npx @electron/rebuild
```

## Architecture

```
Electron App
├── Main Process
│   ├── HotkeyManager (node-global-key-listener)
│   ├── HotkeyStateMachine (PTT vs toggle mode)
│   ├── WhisperEngine (local Whisper inference)
│   ├── AudioCapture (Web Audio API)
│   ├── TextOutput (clipboard + simulated paste)
│   ├── Dictionary (word replacement)
│   └── Tray (menu bar / system tray)
└── Renderer Process
    ├── Status indicator
    ├── Transcription display
    ├── Dictionary editor
    └── Settings
```

## License

MIT
