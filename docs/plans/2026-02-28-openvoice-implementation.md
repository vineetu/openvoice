# OpenVoice Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Windows Electron app for voice dictation using local Whisper (distil-large-v3.5), with push-to-talk/toggle hotkey, clipboard paste, and a custom dictionary.

**Architecture:** Electron main process handles hotkeys, Whisper inference, and text output. Renderer handles audio capture via Web Audio API and UI. Pure logic (dictionary, state machine) is separated from platform code for testability.

**Tech Stack:** Electron 33+, @kutalia/whisper-node-addon, node-global-key-listener, @hurdlegroup/robotjs, electron-store, electron-builder (NSIS), Vitest for testing.

**Dev Note:** We develop on Linux but target Windows. Native addons (whisper-node-addon, robotjs) require Windows for integration testing. All pure logic modules are fully testable on any platform. Platform modules use interfaces so they can be mocked.

---

### Task 1: Project Scaffold

**Files:**
- Create: `package.json`
- Create: `src/main/index.js`
- Create: `src/renderer/index.html`
- Create: `src/preload.js`

**Step 1: Initialize npm project**

Run: `npm init -y`

Edit `package.json`:

```json
{
  "name": "openvoice",
  "version": "0.1.0",
  "description": "Windows voice dictation using local Whisper",
  "main": "src/main/index.js",
  "scripts": {
    "start": "electron .",
    "test": "vitest run",
    "test:watch": "vitest",
    "build": "electron-builder --win"
  },
  "devDependencies": {
    "electron": "^33.0.0",
    "electron-builder": "^26.0.0",
    "vitest": "^3.0.0"
  },
  "dependencies": {
    "@kutalia/whisper-node-addon": "^1.0.0",
    "@hurdlegroup/robotjs": "^0.6.0",
    "node-global-key-listener": "^0.3.0",
    "electron-store": "^10.0.0"
  },
  "build": {
    "appId": "com.openvoice.app",
    "productName": "OpenVoice",
    "win": {
      "target": "nsis",
      "icon": "assets/icon.ico"
    },
    "nsis": {
      "oneClick": false,
      "allowToChangeInstallationDirectory": true
    },
    "files": [
      "src/**/*",
      "assets/**/*"
    ],
    "extraResources": [
      {
        "from": "models/",
        "to": "models/",
        "filter": ["**/*.bin"]
      }
    ]
  }
}
```

**Step 2: Create minimal Electron main process**

Create `src/main/index.js`:

```js
const { app, BrowserWindow } = require('electron');
const path = require('path');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 400,
    height: 500,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, '..', 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

  mainWindow.on('ready-to-show', () => {
    mainWindow.show();
  });
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  app.quit();
});
```

**Step 3: Create minimal preload script**

Create `src/preload.js`:

```js
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('openvoice', {
  getStatus: () => ipcRenderer.invoke('get-status'),
  onStatusChange: (callback) => {
    ipcRenderer.on('status-changed', (_event, status) => callback(status));
  },
});
```

**Step 4: Create minimal renderer**

Create `src/renderer/index.html`:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self'">
  <title>OpenVoice</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <div id="app">
    <h1>OpenVoice</h1>
    <div id="status">Idle</div>
  </div>
  <script src="renderer.js"></script>
</body>
</html>
```

Create `src/renderer/styles.css`:

```css
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Segoe UI', sans-serif; background: #1a1a2e; color: #e0e0e0; padding: 20px; }
h1 { font-size: 24px; margin-bottom: 16px; }
#status { font-size: 18px; padding: 12px; border-radius: 8px; background: #16213e; }
```

Create `src/renderer/renderer.js`:

```js
const statusEl = document.getElementById('status');

window.openvoice.onStatusChange((status) => {
  statusEl.textContent = status;
});
```

**Step 5: Install dev dependencies and verify**

Run: `npm install`
Run: `npx electron --version`
Expected: `v33.x.x`

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: scaffold Electron project with main, preload, and renderer"
```

---

### Task 2: Dictionary Engine (TDD)

Pure function module — no platform dependencies, fully testable.

**Files:**
- Create: `src/main/dictionary.js`
- Create: `tests/dictionary.test.js`

**Step 1: Write failing tests**

Create `tests/dictionary.test.js`:

```js
import { describe, it, expect } from 'vitest';
import { applyDictionary } from '../src/main/dictionary.js';

describe('applyDictionary', () => {
  it('returns text unchanged when dictionary is empty', () => {
    expect(applyDictionary('hello world', {})).toBe('hello world');
  });

  it('replaces a single word match', () => {
    const dict = { btw: 'by the way' };
    expect(applyDictionary('btw that was great', dict)).toBe('by the way that was great');
  });

  it('replaces multiple different words', () => {
    const dict = { btw: 'by the way', addr: '123 Main Street' };
    expect(applyDictionary('btw my addr is here', dict)).toBe('by the way my 123 Main Street is here');
  });

  it('only replaces whole words (word boundary)', () => {
    const dict = { he: 'she' };
    expect(applyDictionary('hello there he said', dict)).toBe('hello there she said');
  });

  it('is case-insensitive for matching', () => {
    const dict = { openai: 'OpenAI' };
    expect(applyDictionary('I work at openai now', dict)).toBe('I work at OpenAI now');
  });

  it('handles multiple occurrences of the same word', () => {
    const dict = { btw: 'by the way' };
    expect(applyDictionary('btw this and btw that', dict)).toBe('by the way this and by the way that');
  });

  it('returns text unchanged when no matches found', () => {
    const dict = { xyz: 'replaced' };
    expect(applyDictionary('hello world', dict)).toBe('hello world');
  });

  it('handles empty text', () => {
    expect(applyDictionary('', { btw: 'by the way' })).toBe('');
  });

  it('escapes regex special characters in dictionary keys', () => {
    const dict = { 'c++': 'C++' };
    expect(applyDictionary('I use c++ daily', dict)).toBe('I use C++ daily');
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/dictionary.test.js`
Expected: FAIL — `applyDictionary` not found

**Step 3: Write minimal implementation**

Create `src/main/dictionary.js`:

```js
function escapeRegExp(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function applyDictionary(text, dictionary) {
  if (!text || !dictionary) return text;

  let result = text;
  for (const [key, value] of Object.entries(dictionary)) {
    const escaped = escapeRegExp(key);
    const regex = new RegExp(`\\b${escaped}\\b`, 'gi');
    result = result.replace(regex, value);
  }
  return result;
}

module.exports = { applyDictionary };
```

**Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/dictionary.test.js`
Expected: All 9 tests PASS

**Step 5: Commit**

```bash
git add src/main/dictionary.js tests/dictionary.test.js
git commit -m "feat: add dictionary engine with word-boundary replacement"
```

---

### Task 3: Hotkey State Machine (TDD)

Pure logic — no Electron dependencies. Emits events based on key timing.

**Files:**
- Create: `src/main/hotkey-state-machine.js`
- Create: `tests/hotkey-state-machine.test.js`

**Step 1: Write failing tests**

Create `tests/hotkey-state-machine.test.js`:

```js
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { HotkeyStateMachine } from '../src/main/hotkey-state-machine.js';

describe('HotkeyStateMachine', () => {
  let sm;
  let onRecordStart;
  let onRecordStop;

  beforeEach(() => {
    onRecordStart = vi.fn();
    onRecordStop = vi.fn();
    sm = new HotkeyStateMachine({
      doubleClickThreshold: 300,
      onRecordStart,
      onRecordStop,
    });
  });

  describe('push-to-talk (hold)', () => {
    it('starts recording on keydown after threshold', () => {
      vi.useFakeTimers();
      sm.keyDown();
      // Wait past double-click threshold
      vi.advanceTimersByTime(350);
      expect(onRecordStart).toHaveBeenCalledTimes(1);
      expect(sm.state).toBe('recording_ptt');
      vi.useRealTimers();
    });

    it('stops recording on keyup in PTT mode', () => {
      vi.useFakeTimers();
      sm.keyDown();
      vi.advanceTimersByTime(350);
      sm.keyUp();
      expect(onRecordStop).toHaveBeenCalledTimes(1);
      expect(sm.state).toBe('idle');
      vi.useRealTimers();
    });

    it('does not start recording if keyup comes before threshold (tap)', () => {
      vi.useFakeTimers();
      sm.keyDown();
      vi.advanceTimersByTime(100);
      sm.keyUp();
      expect(onRecordStart).not.toHaveBeenCalled();
      expect(sm.state).toBe('waiting_for_double');
      vi.useRealTimers();
    });
  });

  describe('toggle mode (double-click)', () => {
    it('starts recording on double-click', () => {
      vi.useFakeTimers();
      // First tap
      sm.keyDown();
      vi.advanceTimersByTime(100);
      sm.keyUp();
      // Second tap within threshold
      vi.advanceTimersByTime(100);
      sm.keyDown();
      sm.keyUp();
      expect(onRecordStart).toHaveBeenCalledTimes(1);
      expect(sm.state).toBe('recording_toggle');
      vi.useRealTimers();
    });

    it('stops recording on next press in toggle mode', () => {
      vi.useFakeTimers();
      // Double-click to start
      sm.keyDown();
      vi.advanceTimersByTime(100);
      sm.keyUp();
      vi.advanceTimersByTime(100);
      sm.keyDown();
      sm.keyUp();
      expect(sm.state).toBe('recording_toggle');
      // Press again to stop
      sm.keyDown();
      sm.keyUp();
      expect(onRecordStop).toHaveBeenCalledTimes(1);
      expect(sm.state).toBe('idle');
      vi.useRealTimers();
    });
  });

  describe('single tap timeout (no second click)', () => {
    it('returns to idle if no second click within threshold', () => {
      vi.useFakeTimers();
      sm.keyDown();
      vi.advanceTimersByTime(100);
      sm.keyUp();
      // Wait past double-click threshold
      vi.advanceTimersByTime(350);
      expect(sm.state).toBe('idle');
      expect(onRecordStart).not.toHaveBeenCalled();
      vi.useRealTimers();
    });
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/hotkey-state-machine.test.js`
Expected: FAIL — `HotkeyStateMachine` not found

**Step 3: Write minimal implementation**

Create `src/main/hotkey-state-machine.js`:

```js
class HotkeyStateMachine {
  constructor({ doubleClickThreshold = 300, onRecordStart, onRecordStop }) {
    this.doubleClickThreshold = doubleClickThreshold;
    this.onRecordStart = onRecordStart;
    this.onRecordStop = onRecordStop;
    this.state = 'idle';
    this._holdTimer = null;
    this._doubleClickTimer = null;
  }

  keyDown() {
    if (this.state === 'idle') {
      this._holdTimer = setTimeout(() => {
        this.state = 'recording_ptt';
        this.onRecordStart();
      }, this.doubleClickThreshold);
    } else if (this.state === 'waiting_for_double') {
      clearTimeout(this._doubleClickTimer);
      this.state = 'pending_double_up';
    } else if (this.state === 'recording_toggle') {
      this.state = 'pending_toggle_stop';
    }
  }

  keyUp() {
    if (this.state === 'recording_ptt') {
      this.state = 'idle';
      this.onRecordStop();
    } else if (this._holdTimer) {
      clearTimeout(this._holdTimer);
      this._holdTimer = null;

      this.state = 'waiting_for_double';
      this._doubleClickTimer = setTimeout(() => {
        if (this.state === 'waiting_for_double') {
          this.state = 'idle';
        }
      }, this.doubleClickThreshold);
    } else if (this.state === 'pending_double_up') {
      this.state = 'recording_toggle';
      this.onRecordStart();
    } else if (this.state === 'pending_toggle_stop') {
      this.state = 'idle';
      this.onRecordStop();
    }
  }

  destroy() {
    clearTimeout(this._holdTimer);
    clearTimeout(this._doubleClickTimer);
  }
}

module.exports = { HotkeyStateMachine };
```

**Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/hotkey-state-machine.test.js`
Expected: All 6 tests PASS

**Step 5: Commit**

```bash
git add src/main/hotkey-state-machine.js tests/hotkey-state-machine.test.js
git commit -m "feat: add hotkey state machine with PTT and toggle modes"
```

---

### Task 4: Settings Module

**Files:**
- Create: `src/main/settings.js`
- Create: `tests/settings.test.js`

**Step 1: Write failing tests**

Create `tests/settings.test.js`:

```js
import { describe, it, expect } from 'vitest';
import { DEFAULTS } from '../src/main/settings.js';

describe('settings defaults', () => {
  it('has correct default hotkey', () => {
    expect(DEFAULTS.hotkey).toBe('Ctrl+Shift+Space');
  });

  it('has correct double-click threshold', () => {
    expect(DEFAULTS.doubleClickThreshold).toBe(300);
  });

  it('has auto-paste enabled by default', () => {
    expect(DEFAULTS.autoPaste).toBe(true);
  });

  it('has correct clipboard restore delay', () => {
    expect(DEFAULTS.clipboardRestoreDelay).toBe(150);
  });

  it('has start with Windows disabled by default', () => {
    expect(DEFAULTS.startWithWindows).toBe(false);
  });

  it('has empty dictionary by default', () => {
    expect(DEFAULTS.dictionary).toEqual({});
  });

  it('has correct model name', () => {
    expect(DEFAULTS.modelName).toBe('ggml-model.bin');
  });

  it('has correct model URL', () => {
    expect(DEFAULTS.modelUrl).toBe('https://huggingface.co/distil-whisper/distil-large-v3.5-ggml/resolve/main/ggml-model.bin');
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/settings.test.js`
Expected: FAIL — `DEFAULTS` not found

**Step 3: Write implementation**

Create `src/main/settings.js`:

```js
const DEFAULTS = {
  hotkey: 'Ctrl+Shift+Space',
  hotkeyPrimary: 'SPACE',
  hotkeyModifiers: ['LEFT CTRL', 'LEFT SHIFT'],
  doubleClickThreshold: 300,
  autoPaste: true,
  clipboardRestoreDelay: 150,
  startWithWindows: false,
  dictionary: {},
  modelName: 'ggml-model.bin',
  modelUrl: 'https://huggingface.co/distil-whisper/distil-large-v3.5-ggml/resolve/main/ggml-model.bin',
  modelDownloaded: false,
  firstLaunchDone: false,
};

let store = null;

function initStore() {
  // Lazy init — electron-store requires Electron's app to be ready
  if (!store) {
    const Store = require('electron-store');
    store = new Store({ defaults: DEFAULTS });
  }
  return store;
}

function getSetting(key) {
  return initStore().get(key);
}

function setSetting(key, value) {
  return initStore().set(key, value);
}

function getAllSettings() {
  return initStore().store;
}

module.exports = { DEFAULTS, initStore, getSetting, setSetting, getAllSettings };
```

**Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/settings.test.js`
Expected: All 8 tests PASS

**Step 5: Commit**

```bash
git add src/main/settings.js tests/settings.test.js
git commit -m "feat: add settings module with electron-store and defaults"
```

---

### Task 5: Model Downloader

Downloads `distil-large-v3.5` GGML model from Hugging Face on first launch. Supports resume for interrupted downloads.

**Files:**
- Create: `src/main/model-downloader.js`
- Create: `tests/model-downloader.test.js`

**Step 1: Write failing tests**

Create `tests/model-downloader.test.js`:

```js
import { describe, it, expect } from 'vitest';
import { getModelUrl, getModelPath } from '../src/main/model-downloader.js';
import { DEFAULTS } from '../src/main/settings.js';

describe('model-downloader', () => {
  it('returns correct Hugging Face URL', () => {
    const url = getModelUrl();
    expect(url).toBe(DEFAULTS.modelUrl);
  });

  it('returns model path under provided base dir', () => {
    const p = getModelPath('/fake/appdata');
    expect(p).toBe('/fake/appdata/models/ggml-model.bin');
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/model-downloader.test.js`
Expected: FAIL — functions not found

**Step 3: Write implementation**

Create `src/main/model-downloader.js`:

```js
const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');
const { DEFAULTS } = require('./settings');

function getModelUrl() {
  return DEFAULTS.modelUrl;
}

function getModelPath(baseDir) {
  return path.join(baseDir, 'models', DEFAULTS.modelName);
}

function modelExists(baseDir) {
  return fs.existsSync(getModelPath(baseDir));
}

/**
 * Get file size for resume support
 */
function getPartialSize(filePath) {
  const partialPath = filePath + '.partial';
  try {
    const stats = fs.statSync(partialPath);
    return stats.size;
  } catch {
    return 0;
  }
}

/**
 * Downloads a model file with progress reporting and resume support.
 * @param {string} baseDir - App data directory
 * @param {function} onProgress - Called with { downloaded, total, percent }
 * @returns {Promise<string>} Path to downloaded model
 */
function downloadModel(baseDir, onProgress) {
  return new Promise((resolve, reject) => {
    const url = getModelUrl();
    const modelPath = getModelPath(baseDir);
    const partialPath = modelPath + '.partial';
    const modelDir = path.dirname(modelPath);

    if (!fs.existsSync(modelDir)) {
      fs.mkdirSync(modelDir, { recursive: true });
    }

    const existingSize = getPartialSize(modelPath);

    function followRedirects(requestUrl, redirectCount = 0) {
      if (redirectCount > 10) {
        reject(new Error('Too many redirects'));
        return;
      }

      const client = requestUrl.startsWith('https') ? https : http;
      const headers = existingSize > 0 ? { Range: `bytes=${existingSize}-` } : {};

      const req = client.get(requestUrl, { headers }, (response) => {
        // Handle redirects
        if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
          followRedirects(response.headers.location, redirectCount + 1);
          return;
        }

        // Handle resume (206) or fresh download (200)
        if (response.statusCode !== 200 && response.statusCode !== 206) {
          reject(new Error(`Download failed: HTTP ${response.statusCode}`));
          return;
        }

        const isResume = response.statusCode === 206;
        const contentLength = parseInt(response.headers['content-length'], 10) || 0;
        const total = isResume ? existingSize + contentLength : contentLength;

        const file = fs.createWriteStream(partialPath, {
          flags: isResume ? 'a' : 'w',
        });

        let downloaded = isResume ? existingSize : 0;

        response.on('data', (chunk) => {
          downloaded += chunk.length;
          if (onProgress && total > 0) {
            onProgress({
              downloaded,
              total,
              percent: Math.round((downloaded / total) * 100),
            });
          }
        });

        response.pipe(file);

        file.on('finish', () => {
          file.close();
          // Rename partial to final
          fs.renameSync(partialPath, modelPath);
          resolve(modelPath);
        });

        file.on('error', (err) => {
          // Don't delete partial file — allows resume
          reject(err);
        });
      });

      req.on('error', (err) => {
        reject(err);
      });
    }

    followRedirects(url);
  });
}

module.exports = { getModelUrl, getModelPath, modelExists, downloadModel };
```

**Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/model-downloader.test.js`
Expected: All 2 tests PASS

**Step 5: Commit**

```bash
git add src/main/model-downloader.js tests/model-downloader.test.js
git commit -m "feat: add model downloader with resume support"
```

---

### Task 6: Whisper Engine Module

Wraps `@kutalia/whisper-node-addon`. Accepts Float32Array PCM directly.

**Files:**
- Create: `src/main/whisper-engine.js`
- Create: `tests/whisper-engine.test.js`

**Step 1: Write failing tests (mocked)**

Create `tests/whisper-engine.test.js`:

```js
import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock the native addon
vi.mock('@kutalia/whisper-node-addon', () => ({
  default: {
    transcribe: vi.fn().mockResolvedValue({
      transcription: [['0:00', '0:05', 'hello world']]
    }),
  },
}));

import { WhisperEngine } from '../src/main/whisper-engine.js';

describe('WhisperEngine', () => {
  let engine;

  beforeEach(() => {
    vi.clearAllMocks();
    engine = new WhisperEngine('/fake/path/model.bin');
  });

  it('stores model path', () => {
    expect(engine.modelPath).toBe('/fake/path/model.bin');
  });

  it('transcribes Float32Array audio and returns text', async () => {
    const pcm = new Float32Array([0.1, 0.2, 0.3]);
    const text = await engine.transcribe(pcm);
    expect(text).toBe('hello world');
  });

  it('passes correct options to whisper addon', async () => {
    const whisper = (await import('@kutalia/whisper-node-addon')).default;
    const pcm = new Float32Array([0.1, 0.2, 0.3]);
    await engine.transcribe(pcm);

    expect(whisper.transcribe).toHaveBeenCalledWith({
      pcmf32: pcm,
      model: '/fake/path/model.bin',
      language: 'en',
      use_gpu: true,
      no_timestamps: true,
    });
  });

  it('returns empty string for empty transcription', async () => {
    const whisper = (await import('@kutalia/whisper-node-addon')).default;
    whisper.transcribe.mockResolvedValueOnce({ transcription: [] });

    const pcm = new Float32Array([0.1, 0.2, 0.3]);
    const text = await engine.transcribe(pcm);
    expect(text).toBe('');
  });

  it('joins multiple segments', async () => {
    const whisper = (await import('@kutalia/whisper-node-addon')).default;
    whisper.transcribe.mockResolvedValueOnce({
      transcription: [
        ['0:00', '0:02', 'hello'],
        ['0:02', '0:05', 'world'],
      ]
    });

    const pcm = new Float32Array([0.1, 0.2, 0.3]);
    const text = await engine.transcribe(pcm);
    expect(text).toBe('hello world');
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/whisper-engine.test.js`
Expected: FAIL — `WhisperEngine` not found

**Step 3: Write implementation**

Create `src/main/whisper-engine.js`:

```js
let whisper;
try {
  whisper = require('@kutalia/whisper-node-addon').default;
} catch {
  whisper = null;
}

class WhisperEngine {
  constructor(modelPath) {
    this.modelPath = modelPath;
  }

  /**
   * Transcribe audio from Float32Array PCM data.
   * @param {Float32Array} pcmf32 - 16kHz mono audio
   * @returns {Promise<string>} Transcribed text
   */
  async transcribe(pcmf32) {
    if (!whisper) throw new Error('whisper-node-addon not available on this platform');

    const result = await whisper.transcribe({
      pcmf32,
      model: this.modelPath,
      language: 'en',
      use_gpu: true,
      no_timestamps: true,
    });

    if (!result || !result.transcription || result.transcription.length === 0) {
      return '';
    }

    // Each segment is [startTime, endTime, text]
    return result.transcription.map((seg) => seg[2]).join(' ').trim();
  }
}

module.exports = { WhisperEngine };
```

**Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/whisper-engine.test.js`
Expected: All 5 tests PASS

**Step 5: Commit**

```bash
git add src/main/whisper-engine.js tests/whisper-engine.test.js
git commit -m "feat: add WhisperEngine with Float32Array PCM support"
```

---

### Task 7: Audio Capture Module (Web Audio API)

Captures microphone audio via Web Audio API in the renderer process, sends Float32Array to main process via IPC.

**Files:**
- Create: `src/renderer/audio-capture.js`
- Create: `src/renderer/audio-worklet-processor.js`
- Modify: `src/preload.js`

**Step 1: Create AudioWorklet processor**

Create `src/renderer/audio-worklet-processor.js`:

```js
class PCMProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.bufferSize = 4096;
    this.buffer = new Float32Array(this.bufferSize);
    this.bufferIndex = 0;
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || !input[0]) return true;

    const channelData = input[0];

    for (let i = 0; i < channelData.length; i++) {
      this.buffer[this.bufferIndex++] = channelData[i];

      if (this.bufferIndex >= this.bufferSize) {
        // Send buffer to main thread
        this.port.postMessage({
          type: 'pcm',
          data: this.buffer.slice(),
        });
        this.bufferIndex = 0;
      }
    }

    return true;
  }
}

registerProcessor('pcm-processor', PCMProcessor);
```

**Step 2: Create audio capture module for renderer**

Create `src/renderer/audio-capture.js`:

```js
class AudioCapture {
  constructor() {
    this.audioContext = null;
    this.mediaStream = null;
    this.workletNode = null;
    this.chunks = [];
    this.isRecording = false;
  }

  async start() {
    if (this.isRecording) return;

    // Request microphone access
    this.mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        sampleRate: 16000,
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
      },
    });

    // Create audio context at 16kHz
    this.audioContext = new AudioContext({ sampleRate: 16000 });

    // Load worklet
    await this.audioContext.audioWorklet.addModule('audio-worklet-processor.js');

    // Create source from microphone
    const source = this.audioContext.createMediaStreamSource(this.mediaStream);

    // Create worklet node
    this.workletNode = new AudioWorkletNode(this.audioContext, 'pcm-processor');

    // Collect PCM chunks
    this.chunks = [];
    this.workletNode.port.onmessage = (event) => {
      if (event.data.type === 'pcm') {
        this.chunks.push(event.data.data);
      }
    };

    // Connect: mic -> worklet
    source.connect(this.workletNode);

    this.isRecording = true;
  }

  stop() {
    if (!this.isRecording) return new Float32Array(0);

    // Stop all tracks
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach((track) => track.stop());
    }

    // Disconnect worklet
    if (this.workletNode) {
      this.workletNode.disconnect();
    }

    // Close audio context
    if (this.audioContext) {
      this.audioContext.close();
    }

    this.isRecording = false;

    // Concatenate all chunks into a single Float32Array
    const totalLength = this.chunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const result = new Float32Array(totalLength);
    let offset = 0;
    for (const chunk of this.chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }

    this.chunks = [];
    return result;
  }

  getIsRecording() {
    return this.isRecording;
  }
}

// Export for use in renderer
window.AudioCapture = AudioCapture;
```

**Step 3: Update preload to expose audio capture IPC**

Update `src/preload.js`:

```js
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('openvoice', {
  getStatus: () => ipcRenderer.invoke('get-status'),
  getSettings: () => ipcRenderer.invoke('get-settings'),
  setSetting: (key, value) => ipcRenderer.invoke('set-setting', key, value),
  getDictionary: () => ipcRenderer.invoke('get-dictionary'),
  setDictionary: (dict) => ipcRenderer.invoke('set-dictionary', dict),

  // Audio capture
  sendAudioData: (pcmFloat32Array) => {
    // Convert Float32Array to regular array for IPC
    ipcRenderer.send('audio-data', Array.from(pcmFloat32Array));
  },

  // Events
  onStatusChange: (callback) => {
    ipcRenderer.on('status-changed', (_event, status) => callback(status));
  },
  onTranscription: (callback) => {
    ipcRenderer.on('transcription', (_event, text) => callback(text));
  },
  onTranscriptionError: (callback) => {
    ipcRenderer.on('transcription-error', (_event, error) => callback(error));
  },
  onDownloadProgress: (callback) => {
    ipcRenderer.on('download-progress', (_event, progress) => callback(progress));
  },
  onStartRecording: (callback) => {
    ipcRenderer.on('start-recording', () => callback());
  },
  onStopRecording: (callback) => {
    ipcRenderer.on('stop-recording', () => callback());
  },
});
```

**Step 4: Commit**

```bash
git add src/renderer/audio-capture.js src/renderer/audio-worklet-processor.js src/preload.js
git commit -m "feat: add Web Audio API capture with AudioWorklet"
```

---

### Task 8: Text Output Module

Clipboard write + simulate Ctrl+V paste + restore clipboard.

**Files:**
- Create: `src/main/text-output.js`
- Create: `tests/text-output.test.js`

**Step 1: Write failing tests (mocked)**

Create `tests/text-output.test.js`:

```js
import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock Electron clipboard
vi.mock('electron', () => ({
  clipboard: {
    readText: vi.fn().mockReturnValue('original clipboard'),
    writeText: vi.fn(),
  },
}));

// Mock robotjs
vi.mock('@hurdlegroup/robotjs', () => ({
  default: {
    keyTap: vi.fn(),
  },
}));

import { pasteText } from '../src/main/text-output.js';
import { clipboard } from 'electron';

describe('pasteText', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('writes text to clipboard', async () => {
    await pasteText('hello world', { autoPaste: false, restoreDelay: 0 });
    expect(clipboard.writeText).toHaveBeenCalledWith('hello world');
  });

  it('preserves original clipboard when auto-pasting', async () => {
    await pasteText('hello world', { autoPaste: true, restoreDelay: 10 });
    // First call saves original, second writes new text, third restores
    const calls = clipboard.writeText.mock.calls;
    expect(calls[0][0]).toBe('hello world');
    // After delay, original should be restored
    await new Promise((r) => setTimeout(r, 50));
    expect(calls[calls.length - 1][0]).toBe('original clipboard');
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/text-output.test.js`
Expected: FAIL — `pasteText` not found

**Step 3: Write implementation**

Create `src/main/text-output.js`:

```js
let electronClipboard;
try {
  electronClipboard = require('electron').clipboard;
} catch {
  electronClipboard = null;
}

let robot;
try {
  robot = require('@hurdlegroup/robotjs');
} catch {
  robot = null;
}

/**
 * Outputs transcribed text via clipboard (and optionally Ctrl+V paste).
 * @param {string} text - Text to output
 * @param {object} options
 * @param {boolean} options.autoPaste - Whether to simulate Ctrl+V
 * @param {number} options.restoreDelay - ms to wait before restoring clipboard
 */
async function pasteText(text, { autoPaste = true, restoreDelay = 150 } = {}) {
  const clipboard = electronClipboard;
  if (!clipboard) throw new Error('Electron clipboard not available');

  const original = autoPaste ? clipboard.readText() : null;

  clipboard.writeText(text);

  if (autoPaste && robot) {
    // Small delay to let clipboard settle
    await sleep(50);
    robot.keyTap('v', 'control');

    // Restore original clipboard after delay
    if (original !== null) {
      await sleep(restoreDelay);
      clipboard.writeText(original);
    }
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = { pasteText };
```

**Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/text-output.test.js`
Expected: All 2 tests PASS

**Step 5: Commit**

```bash
git add src/main/text-output.js tests/text-output.test.js
git commit -m "feat: add text output with clipboard paste and restore"
```

---

### Task 9: Hotkey Manager (node-global-key-listener)

Wraps `node-global-key-listener` to provide keydown/keyup events for global hotkeys.

**Files:**
- Create: `src/main/hotkey-manager.js`

**Step 1: Create hotkey manager**

Create `src/main/hotkey-manager.js`:

```js
let GlobalKeyboardListener;
try {
  GlobalKeyboardListener = require('node-global-key-listener').GlobalKeyboardListener;
} catch {
  GlobalKeyboardListener = null;
}

class HotkeyManager {
  constructor() {
    this.listener = null;
    this.callbacks = { down: null, up: null };
    this.primaryKey = 'SPACE';
    this.modifiers = ['LEFT CTRL', 'LEFT SHIFT'];
  }

  /**
   * Configure the hotkey
   * @param {string} primaryKey - Main key (e.g., 'SPACE', 'F1')
   * @param {string[]} modifiers - Modifier keys (e.g., ['LEFT CTRL', 'LEFT SHIFT'])
   */
  setHotkey(primaryKey, modifiers) {
    this.primaryKey = primaryKey;
    this.modifiers = modifiers;
  }

  /**
   * Start listening for hotkey events
   * @param {object} callbacks - { down: () => void, up: () => void }
   */
  start(callbacks) {
    if (!GlobalKeyboardListener) {
      console.error('node-global-key-listener not available');
      return;
    }

    this.callbacks = callbacks;
    this.listener = new GlobalKeyboardListener();

    this.listener.addListener((event, down) => {
      // Check if primary key matches
      if (event.name !== this.primaryKey) return;

      // Check if all modifiers are held
      const modifiersHeld = this.modifiers.every((mod) => down[mod]);
      if (!modifiersHeld) return;

      // Dispatch event
      if (event.state === 'DOWN' && this.callbacks.down) {
        this.callbacks.down();
      } else if (event.state === 'UP' && this.callbacks.up) {
        this.callbacks.up();
      }
    });
  }

  /**
   * Stop listening
   */
  stop() {
    if (this.listener) {
      this.listener.kill();
      this.listener = null;
    }
  }
}

module.exports = { HotkeyManager };
```

**Step 2: Commit**

```bash
git add src/main/hotkey-manager.js
git commit -m "feat: add HotkeyManager with node-global-key-listener"
```

---

### Task 10: System Tray

**Files:**
- Create: `src/main/tray.js`
- Create: `assets/icon.png` (placeholder — `.ico` needed for Windows, `.png` works for dev)

**Step 1: Create tray module**

Create `src/main/tray.js`:

```js
const { Tray, Menu, nativeImage } = require('electron');
const path = require('path');

let tray = null;

function createTray({ onShowWindow, onStartRecording, onStopRecording, onQuit }) {
  const iconPath = path.join(__dirname, '..', '..', 'assets', 'icon.png');
  tray = new Tray(nativeImage.createFromPath(iconPath));

  tray.setToolTip('OpenVoice — Voice Dictation');

  const contextMenu = Menu.buildFromTemplate([
    { label: 'Show Window', click: onShowWindow },
    { type: 'separator' },
    { label: 'Start Recording', click: onStartRecording },
    { label: 'Stop Recording', click: onStopRecording },
    { type: 'separator' },
    { label: 'Quit', click: onQuit },
  ]);

  tray.setContextMenu(contextMenu);

  tray.on('double-click', onShowWindow);

  return tray;
}

function updateTrayTooltip(text) {
  if (tray) tray.setToolTip(text);
}

function destroyTray() {
  if (tray) {
    tray.destroy();
    tray = null;
  }
}

module.exports = { createTray, updateTrayTooltip, destroyTray };
```

**Step 2: Create placeholder icon**

Run: `mkdir -p assets`

Create a simple 16x16 PNG placeholder (we'll replace with a real `.ico` later):

```bash
# Create a minimal 1x1 pixel PNG as placeholder
node -e "
const fs = require('fs');
// Minimal valid PNG: 1x1 pixel, green
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64');
fs.writeFileSync('assets/icon.png', png);
"
```

**Step 3: Commit**

```bash
git add src/main/tray.js assets/icon.png
git commit -m "feat: add system tray with context menu"
```

---

### Task 11: Main Process Orchestration

Wire all modules together in the main process.

**Files:**
- Modify: `src/main/index.js`

**Step 1: Rewrite main process to wire everything together**

Replace `src/main/index.js`:

```js
const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const { HotkeyStateMachine } = require('./hotkey-state-machine');
const { HotkeyManager } = require('./hotkey-manager');
const { WhisperEngine } = require('./whisper-engine');
const { applyDictionary } = require('./dictionary');
const { pasteText } = require('./text-output');
const { createTray, updateTrayTooltip, destroyTray } = require('./tray');
const { getSetting, setSetting, getAllSettings } = require('./settings');
const { modelExists, downloadModel, getModelPath } = require('./model-downloader');

let mainWindow;
let whisperEngine;
let hotkeyStateMachine;
let hotkeyManager;
let currentStatus = 'idle';
let pendingAudioData = [];

function getAppDataPath() {
  return app.getPath('userData');
}

function setStatus(status) {
  currentStatus = status;
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('status-changed', status);
  }
  updateTrayTooltip(`OpenVoice — ${status}`);
}

function handleRecordStart() {
  setStatus('recording');
  pendingAudioData = [];
  // Tell renderer to start recording
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('start-recording');
  }
}

async function handleRecordStop() {
  setStatus('transcribing');

  // Tell renderer to stop recording
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('stop-recording');
  }

  // Wait a moment for final audio data to arrive
  await new Promise((r) => setTimeout(r, 100));

  try {
    // Combine all audio chunks
    const totalLength = pendingAudioData.reduce((sum, chunk) => sum + chunk.length, 0);
    const pcmf32 = new Float32Array(totalLength);
    let offset = 0;
    for (const chunk of pendingAudioData) {
      pcmf32.set(chunk, offset);
      offset += chunk.length;
    }

    if (pcmf32.length === 0) {
      setStatus('idle');
      return;
    }

    const rawText = await whisperEngine.transcribe(pcmf32);
    const dictionary = getSetting('dictionary');
    const finalText = applyDictionary(rawText, dictionary);

    if (finalText) {
      await pasteText(finalText, {
        autoPaste: getSetting('autoPaste'),
        restoreDelay: getSetting('clipboardRestoreDelay'),
      });
    }

    // Send transcription to renderer for display
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('transcription', finalText);
    }
  } catch (err) {
    console.error('Transcription failed:', err);
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('transcription-error', err.message);
    }
  } finally {
    pendingAudioData = [];
    setStatus('idle');
  }
}

function setupHotkey() {
  hotkeyStateMachine = new HotkeyStateMachine({
    doubleClickThreshold: getSetting('doubleClickThreshold'),
    onRecordStart: handleRecordStart,
    onRecordStop: handleRecordStop,
  });

  hotkeyManager = new HotkeyManager();
  hotkeyManager.setHotkey(
    getSetting('hotkeyPrimary'),
    getSetting('hotkeyModifiers')
  );

  hotkeyManager.start({
    down: () => hotkeyStateMachine.keyDown(),
    up: () => hotkeyStateMachine.keyUp(),
  });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 420,
    height: 560,
    show: false,
    resizable: false,
    webPreferences: {
      preload: path.join(__dirname, '..', 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

  mainWindow.on('close', (event) => {
    // Hide to tray instead of quitting
    event.preventDefault();
    mainWindow.hide();
  });

  mainWindow.on('ready-to-show', () => {
    if (!getSetting('firstLaunchDone')) {
      mainWindow.show();
    }
  });
}

async function initWhisper() {
  const modelPath = getModelPath(getAppDataPath());

  if (!modelExists(getAppDataPath())) {
    setStatus('downloading model');
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
    }

    await downloadModel(getAppDataPath(), (progress) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('download-progress', progress);
      }
    });

    setSetting('modelDownloaded', true);
  }

  setStatus('loading model');
  whisperEngine = new WhisperEngine(modelPath);
  setStatus('idle');
}

// IPC handlers
ipcMain.handle('get-status', () => currentStatus);
ipcMain.handle('get-settings', () => getAllSettings());
ipcMain.handle('set-setting', (_event, key, value) => {
  setSetting(key, value);
  // If hotkey changed, re-setup
  if (key === 'hotkeyPrimary' || key === 'hotkeyModifiers') {
    if (hotkeyManager) hotkeyManager.stop();
    if (hotkeyStateMachine) hotkeyStateMachine.destroy();
    setupHotkey();
  }
});
ipcMain.handle('get-dictionary', () => getSetting('dictionary'));
ipcMain.handle('set-dictionary', (_event, dict) => setSetting('dictionary', dict));

// Receive audio data from renderer
ipcMain.on('audio-data', (_event, audioArray) => {
  pendingAudioData.push(new Float32Array(audioArray));
});

// App lifecycle
app.whenReady().then(async () => {
  createWindow();

  createTray({
    onShowWindow: () => mainWindow && mainWindow.show(),
    onStartRecording: () => handleRecordStart(),
    onStopRecording: () => handleRecordStop(),
    onQuit: () => {
      mainWindow.destroy();
      app.quit();
    },
  });

  try {
    await initWhisper();
    setupHotkey();
    setSetting('firstLaunchDone', true);
  } catch (err) {
    console.error('Initialization failed:', err);
  }
});

app.on('will-quit', () => {
  if (hotkeyManager) hotkeyManager.stop();
  if (hotkeyStateMachine) hotkeyStateMachine.destroy();
  destroyTray();
});

app.on('window-all-closed', () => {
  // Don't quit — keep running in tray
});
```

**Step 2: Commit**

```bash
git add src/main/index.js
git commit -m "feat: wire all modules in main process orchestration"
```

---

### Task 12: Renderer UI

Minimal but functional UI: status, last transcription, dictionary editor, settings.

**Files:**
- Modify: `src/renderer/index.html`
- Modify: `src/renderer/styles.css`
- Modify: `src/renderer/renderer.js`

**Step 1: Build the HTML**

Replace `src/renderer/index.html`:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'">
  <title>OpenVoice</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <div id="app">
    <header>
      <h1>OpenVoice</h1>
      <div id="status-badge" class="status-idle">Idle</div>
    </header>

    <!-- Download Progress (shown during model download) -->
    <section id="download-section" class="hidden">
      <p>Downloading speech model...</p>
      <div class="progress-bar">
        <div id="progress-fill" class="progress-fill"></div>
      </div>
      <span id="progress-text">0%</span>
    </section>

    <!-- Last Transcription -->
    <section id="transcription-section">
      <h2>Last Transcription</h2>
      <div id="transcription-text" class="text-box">Press your hotkey to start dictating</div>
    </section>

    <!-- Tabs -->
    <nav class="tabs">
      <button class="tab active" data-tab="dictionary">Dictionary</button>
      <button class="tab" data-tab="settings">Settings</button>
    </nav>

    <!-- Dictionary Tab -->
    <section id="dictionary-tab" class="tab-content active">
      <div id="dict-entries"></div>
      <div class="dict-add">
        <input id="dict-key" type="text" placeholder="Word heard">
        <input id="dict-value" type="text" placeholder="Replace with">
        <button id="dict-add-btn">Add</button>
      </div>
    </section>

    <!-- Settings Tab -->
    <section id="settings-tab" class="tab-content">
      <label>
        Hotkey
        <input id="setting-hotkey" type="text" readonly>
      </label>
      <label>
        <input id="setting-autopaste" type="checkbox"> Auto-paste into active window
      </label>
      <label>
        <input id="setting-startup" type="checkbox"> Start with Windows
      </label>
    </section>
  </div>
  <script src="audio-capture.js"></script>
  <script src="renderer.js"></script>
</body>
</html>
```

**Step 2: Build the styles**

Replace `src/renderer/styles.css`:

```css
* { margin: 0; padding: 0; box-sizing: border-box; }

body {
  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
  background: #0f0f1a;
  color: #e0e0e0;
  padding: 20px;
  user-select: none;
}

header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
}

h1 { font-size: 22px; font-weight: 600; }
h2 { font-size: 14px; font-weight: 500; margin-bottom: 8px; color: #888; }

#status-badge {
  padding: 4px 12px;
  border-radius: 12px;
  font-size: 12px;
  font-weight: 600;
  text-transform: uppercase;
}

.status-idle { background: #1a2a1a; color: #4ade80; }
.status-recording { background: #2a1a1a; color: #f87171; animation: pulse 1s infinite; }
.status-transcribing { background: #1a1a2a; color: #60a5fa; }
.status-downloading { background: #2a2a1a; color: #fbbf24; }

@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }

.text-box {
  background: #1a1a2e;
  padding: 12px;
  border-radius: 8px;
  font-size: 14px;
  line-height: 1.5;
  min-height: 60px;
  margin-bottom: 16px;
}

.tabs {
  display: flex;
  gap: 4px;
  margin-bottom: 12px;
}

.tab {
  background: #1a1a2e;
  border: none;
  color: #888;
  padding: 8px 16px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 13px;
}

.tab.active { background: #2a2a4e; color: #e0e0e0; }
.tab:hover { background: #2a2a4e; }

.tab-content { display: none; }
.tab-content.active { display: block; }

/* Dictionary */
#dict-entries {
  max-height: 150px;
  overflow-y: auto;
  margin-bottom: 8px;
}

.dict-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 0;
  font-size: 13px;
}

.dict-row .key { color: #60a5fa; min-width: 80px; }
.dict-row .arrow { color: #555; }
.dict-row .value { flex: 1; }
.dict-row button {
  background: none;
  border: none;
  color: #f87171;
  cursor: pointer;
  font-size: 14px;
}

.dict-add {
  display: flex;
  gap: 6px;
}

.dict-add input {
  flex: 1;
  background: #1a1a2e;
  border: 1px solid #333;
  color: #e0e0e0;
  padding: 6px 10px;
  border-radius: 6px;
  font-size: 13px;
}

.dict-add button, #setting-hotkey {
  background: #2a2a4e;
  border: 1px solid #444;
  color: #e0e0e0;
  padding: 6px 12px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 13px;
}

/* Settings */
#settings-tab label {
  display: block;
  margin-bottom: 12px;
  font-size: 13px;
}

#settings-tab input[type="text"] {
  display: block;
  margin-top: 4px;
  width: 100%;
}

#settings-tab input[type="checkbox"] { margin-right: 8px; }

/* Progress bar */
.progress-bar {
  background: #1a1a2e;
  border-radius: 6px;
  height: 8px;
  margin: 8px 0;
  overflow: hidden;
}

.progress-fill {
  background: #60a5fa;
  height: 100%;
  width: 0%;
  transition: width 0.3s;
}

.hidden { display: none; }
```

**Step 3: Build the renderer JS**

Replace `src/renderer/renderer.js`:

```js
const statusBadge = document.getElementById('status-badge');
const transcriptionText = document.getElementById('transcription-text');
const downloadSection = document.getElementById('download-section');
const progressFill = document.getElementById('progress-fill');
const progressText = document.getElementById('progress-text');
const dictEntries = document.getElementById('dict-entries');
const dictKeyInput = document.getElementById('dict-key');
const dictValueInput = document.getElementById('dict-value');
const dictAddBtn = document.getElementById('dict-add-btn');

// Audio capture instance
let audioCapture = new AudioCapture();

// Tabs
document.querySelectorAll('.tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach((t) => t.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach((c) => c.classList.remove('active'));
    tab.classList.add('active');
    document.getElementById(`${tab.dataset.tab}-tab`).classList.add('active');
  });
});

// Status updates
window.openvoice.onStatusChange((status) => {
  statusBadge.textContent = status;
  statusBadge.className = '';

  if (status === 'recording') statusBadge.classList.add('status-recording');
  else if (status === 'transcribing') statusBadge.classList.add('status-transcribing');
  else if (status.includes('download')) statusBadge.classList.add('status-downloading');
  else statusBadge.classList.add('status-idle');

  downloadSection.classList.toggle('hidden', !status.includes('download'));
});

// Recording control from main process
window.openvoice.onStartRecording(async () => {
  await audioCapture.start();
});

window.openvoice.onStopRecording(() => {
  const pcmData = audioCapture.stop();
  window.openvoice.sendAudioData(pcmData);
});

// Transcription display
window.openvoice.onTranscription((text) => {
  transcriptionText.textContent = text || '(empty)';
});

window.openvoice.onTranscriptionError((error) => {
  transcriptionText.textContent = `Error: ${error}`;
});

// Download progress
window.openvoice.onDownloadProgress((progress) => {
  progressFill.style.width = `${progress.percent}%`;
  const mb = (progress.downloaded / 1024 / 1024).toFixed(0);
  const totalMb = (progress.total / 1024 / 1024).toFixed(0);
  progressText.textContent = `${mb} / ${totalMb} MB (${progress.percent}%)`;
});

// Dictionary
let dictionary = {};

async function loadDictionary() {
  dictionary = await window.openvoice.getDictionary();
  renderDictionary();
}

function renderDictionary() {
  dictEntries.innerHTML = '';
  for (const [key, value] of Object.entries(dictionary)) {
    const row = document.createElement('div');
    row.className = 'dict-row';
    row.innerHTML = `
      <span class="key">${key}</span>
      <span class="arrow">&rarr;</span>
      <span class="value">${value}</span>
      <button data-key="${key}">&times;</button>
    `;
    row.querySelector('button').addEventListener('click', () => deleteDictEntry(key));
    dictEntries.appendChild(row);
  }
}

function deleteDictEntry(key) {
  delete dictionary[key];
  window.openvoice.setDictionary(dictionary);
  renderDictionary();
}

dictAddBtn.addEventListener('click', () => {
  const key = dictKeyInput.value.trim().toLowerCase();
  const value = dictValueInput.value.trim();
  if (!key || !value) return;

  dictionary[key] = value;
  window.openvoice.setDictionary(dictionary);
  dictKeyInput.value = '';
  dictValueInput.value = '';
  renderDictionary();
});

// Settings
async function loadSettings() {
  const settings = await window.openvoice.getSettings();
  document.getElementById('setting-hotkey').value = settings.hotkey;
  document.getElementById('setting-autopaste').checked = settings.autoPaste;
  document.getElementById('setting-startup').checked = settings.startWithWindows;
}

document.getElementById('setting-autopaste').addEventListener('change', (e) => {
  window.openvoice.setSetting('autoPaste', e.target.checked);
});

document.getElementById('setting-startup').addEventListener('change', (e) => {
  window.openvoice.setSetting('startWithWindows', e.target.checked);
});

// Init
loadDictionary();
loadSettings();
```

**Step 4: Commit**

```bash
git add src/renderer/index.html src/renderer/styles.css src/renderer/renderer.js
git commit -m "feat: add renderer UI with status, transcription, dictionary, and settings"
```

---

### Task 13: Vitest Config

**Files:**
- Create: `vitest.config.js`

**Step 1: Create vitest config**

Create `vitest.config.js`:

```js
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['tests/**/*.test.js'],
  },
});
```

**Step 2: Run all tests**

Run: `npx vitest run`
Expected: All tests pass (dictionary: 9, state machine: 6, settings: 8, whisper-engine: 5, text-output: 2 = 30 total)

**Step 3: Commit**

```bash
git add vitest.config.js
git commit -m "chore: add vitest config"
```

---

### Task 14: Integration Smoke Test on Windows

This task must be done on a Windows machine.

**Step 1: Clone the repo on a Windows machine**

**Step 2: Install dependencies**

Run: `npm install`

If `@kutalia/whisper-node-addon` or `@hurdlegroup/robotjs` fails, install Visual Studio Build Tools:
```powershell
choco install visualstudio2022-workload-vctools -y
npx @electron/rebuild
```

**Step 3: Run unit tests**

Run: `npm test`
Expected: All tests pass

**Step 4: Start the app in dev mode**

Run: `npm start`
Expected:
- Window appears with "OpenVoice" header
- Status badge shows "downloading model" (if first run)
- Model downloads with progress bar (supports resume if interrupted)
- After download, status shows "loading model" then "idle"
- Tray icon appears in system tray

**Step 5: Test hotkey**

- Press `Ctrl+Shift+Space` — status should change to "recording"
- Speak a phrase
- Release (or press again) — status should change to "transcribing" then back to "idle"
- Transcribed text appears in the text box and is on the clipboard

**Step 6: Test dictionary**

- Add entry: "btw" → "by the way"
- Record "btw this is a test"
- Verify output is "by the way this is a test"

**Step 7: Test auto-paste**

- Open Notepad
- Press hotkey, say something
- Verify text appears in Notepad

**Step 8: Commit any fixes**

```bash
git add -A
git commit -m "fix: integration test fixes from Windows smoke test"
```

---

### Task 15: Build Windows Installer

**Step 1: Build the NSIS installer**

Run (on Windows): `npm run build`
Expected: Creates `dist/OpenVoice Setup 0.1.0.exe`

**Step 2: Test the installer**

- Run the `.exe`
- Install to default location
- Launch from Start Menu
- Verify tray icon, hotkey, recording, and transcription all work

---

## Summary of Fixes Applied

| Original Issue | Fix Applied |
|----------------|-------------|
| Wrong Whisper API (`init`/`free`/`fname_inp`) | Use `transcribe({ pcmf32, model })` with Float32Array |
| Wrong model filename (`ggml-distil-large-v3.5.bin`) | Use `ggml-model.bin` |
| Wrong model URL | Use `https://huggingface.co/distil-whisper/distil-large-v3.5-ggml/resolve/main/ggml-model.bin` |
| No keyup detection (setTimeout hack) | Use `node-global-key-listener` for real keydown/keyup |
| SoX dependency via `node-record-lpcm16` | Use Web Audio API + AudioWorklet (zero external deps) |
| WAV file creation in audio pipeline | Stream Float32Array directly to Whisper |
| No resume support for model download | Added Range header support for resume |
| Missing `node-global-key-listener` in deps | Added to package.json |
