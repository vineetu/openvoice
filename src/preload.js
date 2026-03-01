const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('openvoice', {
  getStatus: () => ipcRenderer.invoke('get-status'),
  getSettings: () => ipcRenderer.invoke('get-settings'),
  setSetting: (key, value) => ipcRenderer.invoke('set-setting', key, value),
  getDictionary: () => ipcRenderer.invoke('get-dictionary'),
  setDictionary: (dict) => ipcRenderer.invoke('set-dictionary', dict),
  pickModelFolder: () => ipcRenderer.invoke('pick-model-folder'),
  startDownload: (folder) => ipcRenderer.invoke('start-download', folder),

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
  onMicPermission: (callback) => {
    ipcRenderer.on('mic-permission', (_event, status) => callback(status));
  },
});
