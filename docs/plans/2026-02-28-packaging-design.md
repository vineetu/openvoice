# OpenVoice — Windows Packaging Design

## Goal

Package the Electron app into a distributable Windows `.exe` installer using GitHub Actions. Bundle SoX so end users don't need to install anything extra.

## Constraints

- Developing on macOS; native modules (`@kutalia/whisper-node-addon`, `@hurdlegroup/robotjs`) must compile on Windows
- Cannot cross-compile from macOS — build must happen on a Windows machine
- GitHub Actions `windows-latest` runner provides the Windows build environment for free (public repo)
- Whisper model (1.5 GB) downloads at first launch, not bundled in installer

## Build Pipeline

```
macOS (dev)                             GitHub Actions (windows-latest)
───────────────                         ──────────────────────────────
git init + commit               →       Checkout code
gh repo create --public --push  →       npm install
                                          → postinstall: electron-builder install-app-deps
                                          → native modules compile for Windows
                                        npm test (47 tests)
                                        Download SoX 14.4.1 Windows binaries → sox-bin/
                                        electron-builder --win
                                          → NSIS installer with src/, assets/, sox-bin/
                                        Upload OpenVoice-Setup-*.exe as artifact
                                ←       Download .exe from Actions tab
```

## Changes Required

### New: `.gitignore`

```
node_modules/
dist/
sox-bin/
*.log
.DS_Store
```

### Update: `.github/workflows/build-windows.yml`

- Add step to download SoX 14.4.1 Windows binary (zip) from SourceForge
- Extract to `sox-bin/` (contains `sox.exe` + DLLs)
- Add SoX GPL license file
- Set `GH_TOKEN` env var for electron-builder

### Update: `package.json` build config

Add `sox-bin/` to `extraResources`:
```json
"extraResources": [
  { "from": "models/", "to": "models/", "filter": ["**/*.bin"] },
  { "from": "assets/", "to": "assets/" },
  { "from": "sox-bin/", "to": "sox-bin/" }
]
```

### Update: `src/main/audio-capture.js`

Before spawning sox, prepend bundled SoX path to PATH when running in packaged app:
```js
if (app.isPackaged) {
  const soxDir = path.join(process.resourcesPath, 'sox-bin');
  process.env.PATH = soxDir + path.delimiter + process.env.PATH;
}
```

`node-record-lpcm16` spawns `sox` as a child process and finds it via PATH.

### New: `README.md`

- Project description
- How to download the installer from GitHub Actions artifacts
- SmartScreen warning: "More info" → "Run anyway"
- First launch: model download (1.5 GB, progress bar)
- Usage: hotkey, dictation, dictionary

## SoX Bundling

- SoX 14.4.1 for Windows (~3 MB): `sox.exe` + required DLLs
- Source: https://sourceforge.net/projects/sox/files/sox/14.4.1/
- License: GPL — include `LICENSE.GPL` alongside the binary
- v14.4.1 recommended over 14.4.2 due to known Windows 10 recording issues with newer version

## Installer Output

- `dist/OpenVoice-Setup-0.1.0.exe` (~80-100 MB estimated)
  - Electron runtime: ~60 MB
  - App code + assets: ~1 MB
  - SoX binaries: ~3 MB
  - Native modules compiled for Windows: ~10-20 MB
- NSIS installer: "Next, Next, Install" wizard
- User can choose install directory

## End User Experience

1. Download `.exe` from GitHub (Actions artifact or future Releases page)
2. Run installer → SmartScreen warning → "More info" → "Run anyway"
3. First launch → Whisper model downloads (1.5 GB, progress bar)
4. App minimizes to system tray → ready to use
5. Press `Ctrl+Shift+Space` to dictate

## Out of Scope

- Code signing (SmartScreen bypass) — documented workaround in README
- Auto-update mechanism
- GitHub Releases publishing (just artifacts for now)
- macOS/Linux builds
