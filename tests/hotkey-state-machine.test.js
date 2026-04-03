import { describe, it, expect, vi, beforeEach } from 'vitest';
import { HotkeyStateMachine } from '../src/main/hotkey-state-machine.js';

describe('HotkeyStateMachine', () => {
  let sm;
  let onRecordStart;
  let onRecordStop;

  beforeEach(() => {
    onRecordStart = vi.fn();
    onRecordStop = vi.fn();
    sm = new HotkeyStateMachine({
      doubleClickThreshold: 300,
      onRecordStart,
      onRecordStop,
    });
  });

  describe('push-to-talk (hold)', () => {
    it('starts recording on keydown after threshold', () => {
      vi.useFakeTimers();
      sm.keyDown();
      // Wait past double-click threshold
      vi.advanceTimersByTime(350);
      expect(onRecordStart).toHaveBeenCalledTimes(1);
      expect(sm.state).toBe('recording_ptt');
      vi.useRealTimers();
    });

    it('stops recording on keyup in PTT mode', () => {
      vi.useFakeTimers();
      sm.keyDown();
      vi.advanceTimersByTime(350);
      sm.keyUp();
      expect(onRecordStop).toHaveBeenCalledTimes(1);
      expect(sm.state).toBe('idle');
      vi.useRealTimers();
    });

    it('does not start recording if keyup comes before threshold (tap)', () => {
      vi.useFakeTimers();
      sm.keyDown();
      vi.advanceTimersByTime(100);
      sm.keyUp();
      expect(onRecordStart).not.toHaveBeenCalled();
      expect(sm.state).toBe('waiting_for_double');
      vi.useRealTimers();
    });
  });

  describe('toggle mode (double-click)', () => {
    it('starts recording on double-click', () => {
      vi.useFakeTimers();
      // First tap
      sm.keyDown();
      vi.advanceTimersByTime(100);
      sm.keyUp();
      // Second tap within threshold
      vi.advanceTimersByTime(100);
      sm.keyDown();
      sm.keyUp();
      expect(onRecordStart).toHaveBeenCalledTimes(1);
      expect(sm.state).toBe('recording_toggle');
      vi.useRealTimers();
    });

    it('stops recording on next press in toggle mode', () => {
      vi.useFakeTimers();
      // Double-click to start
      sm.keyDown();
      vi.advanceTimersByTime(100);
      sm.keyUp();
      vi.advanceTimersByTime(100);
      sm.keyDown();
      sm.keyUp();
      expect(sm.state).toBe('recording_toggle');
      // Press again to stop
      sm.keyDown();
      sm.keyUp();
      expect(onRecordStop).toHaveBeenCalledTimes(1);
      expect(sm.state).toBe('idle');
      vi.useRealTimers();
    });
  });

  describe('single tap timeout (no second click)', () => {
    it('returns to idle if no second click within threshold', () => {
      vi.useFakeTimers();
      sm.keyDown();
      vi.advanceTimersByTime(100);
      sm.keyUp();
      // Wait past double-click threshold
      vi.advanceTimersByTime(350);
      expect(sm.state).toBe('idle');
      expect(onRecordStart).not.toHaveBeenCalled();
      vi.useRealTimers();
    });
  });
});
