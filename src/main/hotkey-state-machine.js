class HotkeyStateMachine {
  constructor({ onRecordStart, onRecordStop }) {
    this.onRecordStart = onRecordStart;
    this.onRecordStop = onRecordStop;
    this.state = 'idle'; // 'idle' | 'recording'
  }

  toggle() {
    if (this.state === 'idle') {
      this.state = 'recording';
      this.onRecordStart();
    } else {
      this.state = 'idle';
      this.onRecordStop();
    }
  }

  destroy() {}
}

module.exports = { HotkeyStateMachine };
