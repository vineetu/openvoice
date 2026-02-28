# OpenVoice Windows Packaging — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Package the OpenVoice Electron app into a distributable Windows `.exe` installer via GitHub Actions, with SoX bundled.

**Architecture:** Create a git repo, push to GitHub, and let the existing GitHub Actions workflow (`.github/workflows/build-windows.yml`) build on `windows-latest`. The workflow downloads SoX, compiles native modules, produces an NSIS installer, and uploads it as a downloadable artifact.

**Tech Stack:** git, GitHub CLI (`gh`), GitHub Actions, electron-builder, NSIS, SoX 14.4.1

---

### Task 1: Create `.gitignore`

**Files:**
- Create: `.gitignore`

**Step 1: Create the file**

```
node_modules/
dist/
sox-bin/
*.log
.DS_Store
```

**Step 2: Verify it exists**

Run: `cat .gitignore`
Expected: Shows the 5 lines above.

**Step 3: Commit (deferred to Task 5)**

No commit yet — we'll do a single initial commit.

---

### Task 2: Add SoX to `extraResources` in `package.json`

**Files:**
- Modify: `package.json:41-51` (the `extraResources` array)

**Step 1: Add `sox-bin/` entry to `extraResources`**

The current `extraResources` array is:
```json
"extraResources": [
  {
    "from": "models/",
    "to": "models/",
    "filter": ["**/*.bin"]
  },
  {
    "from": "assets/",
    "to": "assets/"
  }
]
```

Add a third entry:
```json
"extraResources": [
  {
    "from": "models/",
    "to": "models/",
    "filter": ["**/*.bin"]
  },
  {
    "from": "assets/",
    "to": "assets/"
  },
  {
    "from": "sox-bin/",
    "to": "sox-bin/"
  }
]
```

**Step 2: Verify JSON is valid**

Run: `node -e "require('./package.json')" && echo "OK"`
Expected: `OK`

**Step 3: Run tests to confirm nothing broke**

Run: `npx vitest run`
Expected: 47 tests pass.

---

### Task 3: Update `audio-capture.js` to use bundled SoX

**Files:**
- Modify: `src/main/audio-capture.js:29-36` (the `start()` method)
- Modify: `tests/audio-capture.test.js`

**Step 1: Add bundled SoX PATH prepend in `start()`**

At the top of `audio-capture.js`, after the existing requires, add a helper to get the bundled SoX path. Then in `start()`, before the `checkSoxAvailable()` call, prepend the bundled SoX directory to PATH if it exists.

Add this helper after the `require` block (after line 4):

```js
function prependBundledSoxToPath() {
  // In packaged Electron app, SoX is in extraResources/sox-bin/
  // process.resourcesPath is only defined in packaged Electron apps
  if (typeof process.resourcesPath === 'string') {
    const soxDir = path.join(process.resourcesPath, 'sox-bin');
    if (fs.existsSync(soxDir)) {
      process.env.PATH = soxDir + path.delimiter + (process.env.PATH || '');
    }
  }
}
```

Then in `start()`, call it before the SoX check. Replace lines 29-36:

```js
  start() {
    if (!this._record) throw new Error('node-record-lpcm16 not available');
    if (this._recording) return;
    prependBundledSoxToPath();
    if (!AudioCapture.checkSoxAvailable()) {
      throw new Error(
        'SoX not found. Install SoX (sox.sourceforge.net) and ensure it is on your PATH.'
      );
    }
```

Note: We use `process.resourcesPath` existence check instead of `app.isPackaged` because `audio-capture.js` doesn't import Electron's `app` module and shouldn't need to — `process.resourcesPath` is set by Electron automatically in packaged apps.

**Step 2: Run tests**

Run: `npx vitest run`
Expected: 47 tests pass. The existing mock on `checkSoxAvailable` prevents the real SoX check from running in tests. The `prependBundledSoxToPath()` call is a no-op in test (no `process.resourcesPath`).

---

### Task 4: Update GitHub Actions workflow

**Files:**
- Modify: `.github/workflows/build-windows.yml`

**Step 1: Rewrite the workflow**

Replace the entire file with:

```yaml
name: Build Windows Installer

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20

      - name: Install dependencies
        run: npm install

      - name: Run tests
        run: npm test

      - name: Download and extract SoX
        shell: pwsh
        run: |
          $url = "https://sourceforge.net/projects/sox/files/sox/14.4.1/sox-14.4.1a-win32.zip/download"
          Invoke-WebRequest -Uri $url -OutFile sox.zip -UserAgent "Mozilla/5.0"
          Expand-Archive -Path sox.zip -DestinationPath sox-extract
          New-Item -ItemType Directory -Force -Path sox-bin
          Copy-Item sox-extract/sox-14.4.1/* sox-bin/ -Recurse
          Remove-Item sox.zip, sox-extract -Recurse -Force

      - name: Verify SoX binary
        run: sox-bin\sox.exe --version

      - name: Build Windows installer
        run: npm run build
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Upload installer artifact
        uses: actions/upload-artifact@v4
        with:
          name: OpenVoice-Windows-Installer
          path: dist/OpenVoice-Setup-*.exe
          if-no-files-found: error

      - name: Upload unpacked build
        uses: actions/upload-artifact@v4
        with:
          name: OpenVoice-Windows-Unpacked
          path: dist/win-unpacked/
```

Key changes from original:
- Added "Download and extract SoX" step using PowerShell
- Added "Verify SoX binary" step to confirm the download worked
- Added `GH_TOKEN` env var to the build step (avoids GitHub API rate limits when electron-builder downloads Electron)
- The SoX zip extracts to a subdirectory named `sox-14.4.1/` — we copy its contents to `sox-bin/` which matches our `extraResources` config

**Step 2: Verify YAML syntax**

Run: `node -e "const yaml = require('yaml'); yaml.parse(require('fs').readFileSync('.github/workflows/build-windows.yml','utf8')); console.log('OK')"`

Note: If `yaml` isn't installed, just visually confirm the indentation is correct. The real validation happens when GitHub parses it.

---

### Task 5: Create README.md

**Files:**
- Create: `README.md`

**Step 1: Create the file**

```markdown
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
```

---

### Task 6: Initialize git repo, commit, and push to GitHub

**Step 1: Initialize git**

Run: `git init`
Expected: `Initialized empty Git repository`

**Step 2: Stage all files**

Run: `git add .`

Then verify nothing unexpected is staged:
Run: `git status`
Expected: `node_modules/`, `dist/`, `.DS_Store` should NOT appear (blocked by `.gitignore`). Source files, assets, workflow, docs, package.json should all be staged.

**Step 3: Create initial commit**

Run:
```bash
git commit -m "Initial commit: OpenVoice Windows voice dictation app

Electron app with local Whisper inference, global hotkey recording,
clipboard paste output, dictionary word replacement, and system tray.
GitHub Actions workflow builds Windows installer with bundled SoX."
```

**Step 4: Create GitHub repository and push**

Run:
```bash
gh repo create openvoice --public --source=. --push
```

Expected: Creates `https://github.com/vineetu/openvoice` (or similar), sets remote, pushes `main` branch.

**Step 5: Verify push triggered the workflow**

Run: `gh run list --limit 1`
Expected: Shows a "Build Windows Installer" run in progress or queued.

---

### Task 7: Monitor the build and troubleshoot

**Step 1: Watch the build**

Run: `gh run watch`
This streams build logs live. Watch for:
- `npm install` succeeds (native modules compile)
- `npm test` passes (47 tests)
- SoX download completes
- `electron-builder --win` produces the installer
- Artifacts upload

**Step 2: If the build succeeds**

Run: `gh run download --name OpenVoice-Windows-Installer --dir ./dist-download`
Expected: Downloads the `.exe` to `./dist-download/`

**Step 3: If the build fails**

Run: `gh run view --log-failed`
Read the failure logs. Common issues:
- **SoX download fails**: SourceForge can be flaky. The workflow may need a retry or a mirror URL.
- **Native module compile fails**: Missing build tools on the runner. May need to add `windows-build-tools` step.
- **electron-builder fails**: Usually a path or config issue. Check the error message carefully.

Fix the issue, commit, push. The workflow re-triggers automatically.

---

## Summary

| Task | What | Files |
|---|---|---|
| 1 | Create `.gitignore` | `.gitignore` |
| 2 | Add SoX to `extraResources` | `package.json` |
| 3 | Bundled SoX PATH in audio-capture | `src/main/audio-capture.js` |
| 4 | Update GitHub Actions workflow | `.github/workflows/build-windows.yml` |
| 5 | Create README | `README.md` |
| 6 | Git init + commit + push to GitHub | (git operations) |
| 7 | Monitor build + download artifact | (GitHub Actions) |
