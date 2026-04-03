const isMac = process.platform === 'darwin';

const DEFAULTS = {
  // Platform-aware hotkey defaults
  hotkey: isMac ? 'Cmd+Shift+Space' : 'Ctrl+Shift+Space',
  hotkeyPrimary: 'SPACE',
  hotkeyModifiers: isMac ? ['LEFT META', 'LEFT SHIFT'] : ['LEFT CTRL', 'LEFT SHIFT'],
  doubleClickThreshold: 300,
  autoPaste: true,
  clipboardRestoreDelay: 150,
  startAtLogin: false,
  dictionary: {},
  modelName: 'ggml-small.en.bin',
  modelUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin',
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
