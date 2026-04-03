class HotkeyStateMachine {
  constructor({ doubleClickThreshold = 300, onRecordStart, onRecordStop }) {
    this.doubleClickThreshold = doubleClickThreshold;
    this.onRecordStart = onRecordStart;
    this.onRecordStop = onRecordStop;
    this.state = 'idle';
    this._holdTimer = null;
    this._doubleClickTimer = null;
  }

  keyDown() {
    if (this.state === 'idle') {
      this._holdTimer = setTimeout(() => {
        this.state = 'recording_ptt';
        this.onRecordStart();
      }, this.doubleClickThreshold);
    } else if (this.state === 'waiting_for_double') {
      clearTimeout(this._doubleClickTimer);
      this.state = 'pending_double_up';
    } else if (this.state === 'recording_toggle') {
      this.state = 'pending_toggle_stop';
    }
  }

  keyUp() {
    if (this.state === 'recording_ptt') {
      this.state = 'idle';
      this.onRecordStop();
    } else if (this._holdTimer) {
      clearTimeout(this._holdTimer);
      this._holdTimer = null;

      this.state = 'waiting_for_double';
      this._doubleClickTimer = setTimeout(() => {
        if (this.state === 'waiting_for_double') {
          this.state = 'idle';
        }
      }, this.doubleClickThreshold);
    } else if (this.state === 'pending_double_up') {
      this.state = 'recording_toggle';
      this.onRecordStart();
    } else if (this.state === 'pending_toggle_stop') {
      this.state = 'idle';
      this.onRecordStop();
    }
  }

  destroy() {
    clearTimeout(this._holdTimer);
    clearTimeout(this._doubleClickTimer);
  }
}

module.exports = { HotkeyStateMachine };
