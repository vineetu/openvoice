import { describe, it, expect } from 'vitest';
import { DEFAULTS } from '../src/main/settings.js';

describe('settings defaults', () => {
  it('has correct default hotkey', () => {
    expect(DEFAULTS.hotkey).toBe('Ctrl+Shift+Space');
  });

  it('has auto-paste enabled by default', () => {
    expect(DEFAULTS.autoPaste).toBe(true);
  });

  it('has correct clipboard restore delay', () => {
    expect(DEFAULTS.clipboardRestoreDelay).toBe(150);
  });

  it('has start with Windows disabled by default', () => {
    expect(DEFAULTS.startWithWindows).toBe(false);
  });

  it('has empty dictionary by default', () => {
    expect(DEFAULTS.dictionary).toEqual({});
  });

  it('has correct model name', () => {
    expect(DEFAULTS.modelName).toBe('ggml-distil-large-v3.5.bin');
  });
});
