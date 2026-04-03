const isMac = process.platform === 'darwin';

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
 * Outputs transcribed text via clipboard (and optionally paste).
 * Uses Cmd+V on Mac, Ctrl+V on Windows.
 * @param {string} text - Text to output
 * @param {object} options
 * @param {boolean} options.autoPaste - Whether to simulate paste keystroke
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

    // Platform-aware paste: Cmd+V on Mac, Ctrl+V on Windows
    const modifier = isMac ? 'command' : 'control';
    robot.keyTap('v', modifier);

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
