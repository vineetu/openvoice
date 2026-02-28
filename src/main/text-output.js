let defaultClipboard;
try {
  defaultClipboard = require('electron').clipboard;
} catch {
  defaultClipboard = null;
}

let defaultRobot;
try {
  defaultRobot = require('@hurdlegroup/robotjs');
} catch {
  defaultRobot = null;
}

/**
 * Outputs transcribed text via clipboard (and optionally Ctrl+V paste).
 * @param {string} text - Text to output
 * @param {object} options
 * @param {boolean} options.autoPaste - Whether to simulate Ctrl+V
 * @param {number} options.restoreDelay - ms to wait before restoring clipboard
 * @param {object} options.clipboard - Optional clipboard module (for testing)
 * @param {object} options.robot - Optional robotjs module (for testing)
 */
async function pasteText(text, { autoPaste = true, restoreDelay = 150, clipboard, robot } = {}) {
  clipboard = clipboard || defaultClipboard;
  robot = robot || defaultRobot;
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
