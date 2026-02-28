# OpenVoice

Windows voice dictation app. Press a hotkey, speak, and transcribed text appears in whatever app you're using. Runs Whisper locally — no internet, no API keys, full privacy.

## Install

1. Go to [Actions](../../actions) → click the latest green **Build Windows Installer** run
2. Scroll to **Artifacts** and download **OpenVoice-Windows-Installer**
3. Extract the zip and run **OpenVoice Setup 0.1.0.exe**
4. If Windows SmartScreen appears, click **More info** → **Run anyway** (the app is not code-signed yet)

## First Launch

On first launch the app will:
1. Open the main window and download the Whisper speech model (~1.5 GB). A progress bar shows status.
2. Load the model into memory (takes a few seconds).
3. Minimize to the **system tray** (bottom-right of the taskbar) once ready.

No internet connection is needed after the model is downloaded.

## Usage

| Action | What happens |
|---|---|
| Press **Ctrl+Shift+Space** | Start recording (orb pulses) |
| Press **Ctrl+Shift+Space** again | Stop recording → transcribe → paste into active window |

Transcribed text is copied to the clipboard and auto-pasted (Ctrl+V) into whatever app has focus.

### Tray icon

Right-click the tray icon to:
- **Show Window** — open the main UI
- **Start / Stop Recording** — same as the hotkey
- **Quit** — fully exit the app

### Closing vs quitting

Clicking the window **X** button hides the app to the tray (it keeps running). To fully quit, use **Quit** from the tray menu.

## Features

- **Dictionary** — Add custom word replacements for words Whisper gets wrong (e.g., proper nouns, brand names)
- **System tray** — Runs in the background, always one hotkey away
- **Settings** — Configurable hotkey, auto-paste toggle, launch-on-startup option

## Development

Requires Node.js 20+ and SoX on PATH (for microphone capture).

```bash
npm install
npm test        # 48 tests via vitest
npm start       # launch in dev mode
```

Build the Windows installer locally (requires Windows):

```bash
npm run build   # outputs to dist/
```

## License

MIT
