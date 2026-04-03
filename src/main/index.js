const { app, BrowserWindow, ipcMain, systemPreferences } = require('electron');
const path = require('path');
const { HotkeyStateMachine } = require('./hotkey-state-machine');
const { HotkeyManager } = require('./hotkey-manager');
const { WhisperEngine } = require('./whisper-engine');
const { applyDictionary } = require('./dictionary');
const { pasteText } = require('./text-output');
const { createTray, updateTrayTooltip, destroyTray } = require('./tray');
const { getSetting, setSetting, getAllSettings, DEFAULTS } = require('./settings');
const { modelExists, downloadModel, getModelPath } = require('./model-downloader');

const isMac = process.platform === 'darwin';

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
    titleBarStyle: isMac ? 'hiddenInset' : 'default',
    webPreferences: {
      preload: path.join(__dirname, '..', 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

  mainWindow.on('close', (event) => {
    // Hide to tray instead of quitting
    if (!app.isQuiting) {
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

async function checkMacPermissions() {
  if (!isMac) return true;

  // Check microphone permission
  const micStatus = systemPreferences.getMediaAccessStatus('microphone');
  if (micStatus !== 'granted') {
    // Request permission - will prompt user
    const granted = await systemPreferences.askForMediaAccess('microphone');
    if (!granted) {
      console.warn('Microphone permission denied');
      return false;
    }
  }

  // Note: Accessibility permission is checked at runtime by node-global-key-listener
  // We can't programmatically request it, but we can check if it's granted
  const accessibilityGranted = systemPreferences.isTrustedAccessibilityClient(false);
  if (!accessibilityGranted) {
    console.warn('Accessibility permission not granted. Global hotkeys may not work.');
    // Show window with instructions
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
      mainWindow.webContents.send('permission-required', 'accessibility');
    }
  }

  return true;
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
ipcMain.handle('get-platform', () => process.platform);

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
      app.isQuiting = true;
      mainWindow.destroy();
      app.quit();
    },
  });

  try {
    await checkMacPermissions();
    await initWhisper();
    setupHotkey();
    setSetting('firstLaunchDone', true);
  } catch (err) {
    console.error('Initialization failed:', err);
  }
});

app.on('activate', () => {
  // macOS: re-create window when dock icon is clicked
  if (mainWindow === null) {
    createWindow();
  } else {
    mainWindow.show();
  }
});

app.on('before-quit', () => {
  app.isQuiting = true;
});

app.on('will-quit', () => {
  if (hotkeyManager) hotkeyManager.stop();
  if (hotkeyStateMachine) hotkeyStateMachine.destroy();
  destroyTray();
});

app.on('window-all-closed', () => {
  // Don't quit on macOS — keep running in menu bar
  if (!isMac) {
    // On Windows, don't quit either — keep running in tray
  }
});
