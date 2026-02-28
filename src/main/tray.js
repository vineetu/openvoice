const { app, Tray, Menu, nativeImage } = require('electron');
const path = require('path');

let tray = null;

function getIconPath() {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'assets', 'icon.png');
  }
  return path.join(__dirname, '..', '..', 'assets', 'icon.png');
}

function createTray({ onShowWindow, onStartRecording, onStopRecording, onQuit }) {
  const iconPath = getIconPath();
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

module.exports = { createTray, updateTrayTooltip, destroyTray, getIconPath };
