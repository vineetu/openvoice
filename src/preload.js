const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('openvoice', {
  getStatus: () => ipcRenderer.invoke('get-status'),
  getSettings: () => ipcRenderer.invoke('get-settings'),
  setSetting: (key, value) => ipcRenderer.invoke('set-setting', key, value),
  getDictionary: () => ipcRenderer.invoke('get-dictionary'),
  setDictionary: (dict) => ipcRenderer.invoke('set-dictionary', dict),
  getPlatform: () => ipcRenderer.invoke('get-platform'),

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
  onPermissionRequired: (callback) => {
    ipcRenderer.on('permission-required', (_event, permission) => callback(permission));
  },
});
