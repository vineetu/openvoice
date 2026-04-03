let GlobalKeyboardListener;
try {
  GlobalKeyboardListener = require('node-global-key-listener').GlobalKeyboardListener;
} catch {
  GlobalKeyboardListener = null;
}

class HotkeyManager {
  constructor() {
    this.listener = null;
    this.callbacks = { down: null, up: null };
    this.primaryKey = 'SPACE';
    // Default to Mac modifiers if on Mac, otherwise Windows
    const isMac = process.platform === 'darwin';
    this.modifiers = isMac ? ['LEFT META', 'LEFT SHIFT'] : ['LEFT CTRL', 'LEFT SHIFT'];
  }

  /**
   * Configure the hotkey
   * @param {string} primaryKey - Main key (e.g., 'SPACE', 'F1')
   * @param {string[]} modifiers - Modifier keys (e.g., ['LEFT CTRL', 'LEFT SHIFT'] or ['LEFT META', 'LEFT SHIFT'])
   */
  setHotkey(primaryKey, modifiers) {
    this.primaryKey = primaryKey;
    this.modifiers = modifiers;
  }

  /**
   * Start listening for hotkey events
   * @param {object} callbacks - { down: () => void, up: () => void }
   */
  start(callbacks) {
    if (!GlobalKeyboardListener) {
      console.error('node-global-key-listener not available');
      return;
    }

    this.callbacks = callbacks;
    this.listener = new GlobalKeyboardListener();

    this.listener.addListener((event, down) => {
      // Check if primary key matches
      if (event.name !== this.primaryKey) return;

      // Check if all modifiers are held
      const modifiersHeld = this.modifiers.every((mod) => down[mod]);
      if (!modifiersHeld) return;

      // Dispatch event
      if (event.state === 'DOWN' && this.callbacks.down) {
        this.callbacks.down();
      } else if (event.state === 'UP' && this.callbacks.up) {
        this.callbacks.up();
      }
    });
  }

  /**
   * Stop listening
   */
  stop() {
    if (this.listener) {
      this.listener.kill();
      this.listener = null;
    }
  }
}

module.exports = { HotkeyManager };
