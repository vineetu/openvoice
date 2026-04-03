const { Tray, Menu, nativeImage } = require('electron');
const path = require('path');

const isMac = process.platform === 'darwin';

let tray = null;

function createTray({ onShowWindow, onStartRecording, onStopRecording, onQuit }) {
  // Use different icon for Mac (template image) vs Windows (.ico)
  const iconName = isMac ? 'iconTemplate.png' : 'icon.png';
  const iconPath = path.join(__dirname, '..', '..', 'assets', iconName);

  let icon = nativeImage.createFromPath(iconPath);

  // For macOS, mark as template image (system will handle dark/light mode)
  if (isMac) {
    icon = icon.resize({ width: 18, height: 18 });
    icon.setTemplateImage(true);
  }

  tray = new Tray(icon);

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

  // Double-click to show window (works on Windows, not reliable on Mac)
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
