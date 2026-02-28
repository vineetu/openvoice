import { describe, it, expect, vi, beforeEach } from 'vitest';
import { HotkeyStateMachine } from '../src/main/hotkey-state-machine.js';

describe('HotkeyStateMachine', () => {
  let sm;
  let onRecordStart;
  let onRecordStop;

  beforeEach(() => {
    onRecordStart = vi.fn();
    onRecordStop = vi.fn();
    sm = new HotkeyStateMachine({ onRecordStart, onRecordStop });
  });

  it('starts idle', () => {
    expect(sm.state).toBe('idle');
  });

  it('starts recording on first toggle', () => {
    sm.toggle();
    expect(onRecordStart).toHaveBeenCalledTimes(1);
    expect(sm.state).toBe('recording');
  });

  it('stops recording on second toggle', () => {
    sm.toggle(); // start
    sm.toggle(); // stop
    expect(onRecordStop).toHaveBeenCalledTimes(1);
    expect(sm.state).toBe('idle');
  });

  it('can toggle multiple cycles', () => {
    sm.toggle(); // start
    sm.toggle(); // stop
    sm.toggle(); // start again
    expect(onRecordStart).toHaveBeenCalledTimes(2);
    expect(sm.state).toBe('recording');
    sm.toggle(); // stop again
    expect(onRecordStop).toHaveBeenCalledTimes(2);
    expect(sm.state).toBe('idle');
  });
});
