const { app, BrowserWindow, globalShortcut, ipcMain, systemPreferences } = require('electron');
const path = require('path');
const { HotkeyStateMachine } = require('./hotkey-state-machine');
const { WhisperEngine } = require('./whisper-engine');
const { AudioCapture } = require('./audio-capture');
const { applyDictionary } = require('./dictionary');
const { pasteText } = require('./text-output');
const { createTray, updateTrayTooltip, destroyTray } = require('./tray');
const { getSetting, setSetting, getAllSettings, DEFAULTS } = require('./settings');
const { modelExists, downloadModel, getModelPath } = require('./model-downloader');

let mainWindow;
let whisperEngine;
let audioCapture;
let hotkeyStateMachine;
let currentStatus = 'idle';
let isQuitting = false;

function getAppDataPath() {
  return path.join(app.getPath('userData'));
}

function setStatus(status) {
  currentStatus = status;
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('status-changed', status);
  }
  updateTrayTooltip(`OpenVoice — ${status}`);
}

async function handleRecordStart() {
  if (audioCapture) return; // Already recording
  setStatus('recording');
  audioCapture = new AudioCapture();
  try {
    audioCapture.start();
  } catch (err) {
    console.error('Recording failed to start:', err);
    audioCapture = null;
    setStatus('error: ' + err.message);
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('transcription-error', err.message);
      mainWindow.show();
    }
  }
}

async function handleRecordStop() {
  // Capture local reference and clear immediately to prevent race conditions
  // if the user rapidly toggles (start → stop → start while transcription runs)
  const capture = audioCapture;
  if (!capture) return;
  audioCapture = null;

  setStatus('transcribing');

  try {
    const wavPath = await capture.stop();
    const rawText = await whisperEngine.transcribe(wavPath);
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
    capture.cleanup();
    // Only reset to idle if no new recording started during transcription
    if (!audioCapture) {
      setStatus('idle');
    }
  }
}

function registerHotkey() {
  const hotkey = getSetting('hotkey');

  hotkeyStateMachine = new HotkeyStateMachine({
    onRecordStart: handleRecordStart,
    onRecordStop: handleRecordStop,
  });

  const registered = globalShortcut.register(hotkey, () => {
    hotkeyStateMachine.toggle();
  });

  if (!registered) {
    console.error(`Failed to register hotkey: ${hotkey}`);
    setStatus(`error: hotkey "${hotkey}" is already in use by another app`);
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
    }
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 680,
    height: 720,
    show: false,
    resizable: true,
    minWidth: 580,
    minHeight: 600,
    frame: false,
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      preload: path.join(__dirname, '..', 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

  mainWindow.on('close', (event) => {
    if (!isQuitting) {
      // Hide to tray instead of quitting
      event.preventDefault();
      mainWindow.hide();
    }
  });

  mainWindow.on('ready-to-show', () => {
    if (!getSetting('firstLaunchDone')) {
      mainWindow.show();
    }
  });
}

async function initWhisper() {
  whisperEngine = new WhisperEngine();
  const modelName = getSetting('modelName');
  const modelPath = getModelPath(getAppDataPath(), modelName);

  if (!modelExists(getAppDataPath(), modelName)) {
    setStatus('downloading model');
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
    }

    await downloadModel(getAppDataPath(), modelName, (progress) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('download-progress', progress);
      }
    });

    setSetting('modelDownloaded', true);
  }

  setStatus('loading model');
  await whisperEngine.loadModel(modelPath);
  setStatus('idle');
}

// IPC handlers
const WRITABLE_SETTINGS = new Set(['hotkey', 'autoPaste', 'startWithWindows']);
const VALID_HOTKEY = /^(Ctrl\+|Alt\+|Shift\+|Super\+|CmdOrCtrl\+)+(F\d{1,2}|[A-Z]|Space|[0-9])$/;

ipcMain.handle('get-status', () => currentStatus);
ipcMain.handle('get-settings', () => ({
  hotkey: getSetting('hotkey'),
  autoPaste: getSetting('autoPaste'),
  startWithWindows: getSetting('startWithWindows'),
}));
ipcMain.handle('set-setting', (_event, key, value) => {
  if (!WRITABLE_SETTINGS.has(key)) {
    throw new Error(`Setting not allowed: ${key}`);
  }
  if (key === 'hotkey') {
    if (typeof value !== 'string' || !VALID_HOTKEY.test(value)) {
      throw new Error(`Invalid hotkey format: ${value}`);
    }
    setSetting(key, value);
    globalShortcut.unregisterAll();
    registerHotkey();
    return;
  }
  if (key === 'autoPaste' || key === 'startWithWindows') {
    setSetting(key, !!value);
  }
  if (key === 'startWithWindows') {
    app.setLoginItemSettings({ openAtLogin: !!value });
  }
});
ipcMain.handle('get-dictionary', () => getSetting('dictionary'));

// Fix #2: Validate dictionary input
ipcMain.handle('set-dictionary', (_event, dict) => {
  if (typeof dict !== 'object' || dict === null || Array.isArray(dict)) {
    throw new Error('Invalid dictionary');
  }
  const entries = Object.entries(dict);
  if (entries.length > 500) throw new Error('Dictionary too large');
  for (const [k, v] of entries) {
    if (typeof k !== 'string' || typeof v !== 'string') {
      throw new Error('Dictionary entries must be strings');
    }
    if (k.length > 200 || v.length > 200) {
      throw new Error('Dictionary entry too long');
    }
  }
  setSetting('dictionary', dict);
});

// App lifecycle
app.whenReady().then(async () => {
  createWindow();

  createTray({
    onShowWindow: () => mainWindow && mainWindow.show(),
    onStartRecording: () => {
      if (hotkeyStateMachine && hotkeyStateMachine.state === 'idle') {
        hotkeyStateMachine.toggle();
      }
    },
    onStopRecording: () => {
      if (hotkeyStateMachine && hotkeyStateMachine.state === 'recording') {
        hotkeyStateMachine.toggle();
      }
    },
    onQuit: () => {
      isQuitting = true;
      app.quit();
    },
  });

  // Apply start-with-Windows setting
  app.setLoginItemSettings({ openAtLogin: !!getSetting('startWithWindows') });

  // Check microphone permission
  const micStatus = systemPreferences.getMediaAccessStatus('microphone');
  if (micStatus !== 'granted') {
    console.warn(`Microphone access: ${micStatus}`);
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('mic-permission', micStatus);
      mainWindow.show();
    }
  }

  try {
    await initWhisper();
    registerHotkey();
    setSetting('firstLaunchDone', true);
  } catch (err) {
    console.error('Initialization failed:', err);
    setStatus('error: ' + err.message);
    // Still show window so user can see the error
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
    }
  }
});

app.on('before-quit', () => {
  isQuitting = true;
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
  if (whisperEngine) whisperEngine.unload();
  if (hotkeyStateMachine) hotkeyStateMachine.destroy();
  destroyTray();
});

app.on('window-all-closed', () => {
  // Don't quit — keep running in tray
});
