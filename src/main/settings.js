const DEFAULTS = {
  hotkey: 'Ctrl+Shift+Space',
  autoPaste: true,
  clipboardRestoreDelay: 150,
  startWithWindows: false,
  dictionary: {},
  modelName: 'ggml-distil-large-v3.5.bin',
  modelDownloaded: false,
  firstLaunchDone: false,
  modelStoragePath: '',
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
