# OpenVoice

Windows voice dictation app. Press a hotkey, speak, and transcribed text appears in whatever app you're using. Runs Whisper locally — no internet, no API keys, full privacy.

## Download

1. Go to [Actions](../../actions) → click the latest successful **Build Windows Installer** run
2. Download the **OpenVoice-Windows-Installer** artifact
3. Extract the zip and run `OpenVoice-Setup-0.1.0.exe`

## First Launch

- **SmartScreen warning**: Click "More info" → "Run anyway" (app is not code-signed yet)
- **Model download**: The app downloads the Whisper model (~1.5 GB) on first launch. A progress bar shows download status.
- After the model loads, the app minimizes to the system tray.

## Usage

| Action | What happens |
|---|---|
| Press `Ctrl+Shift+Space` | Start recording |
| Press `Ctrl+Shift+Space` again | Stop recording, transcribe, paste into active window |

Transcribed text is automatically pasted into whatever app has focus (via clipboard + Ctrl+V).

## Features

- **Dictionary**: Add custom word replacements for words Whisper gets wrong (e.g., proper nouns, abbreviations)
- **System tray**: App runs in the background, accessible from the tray icon
- **Settings**: Configurable hotkey, auto-paste toggle, launch-on-startup

## Development

Requires Node.js 20+ and SoX installed on PATH (for microphone recording).

```bash
npm install
npm test
npm start
```

## License

MIT
