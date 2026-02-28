import { describe, it, expect, vi, beforeEach } from 'vitest';
import { pasteText } from '../src/main/text-output.js';

describe('pasteText', () => {
  let mockClipboard;
  let mockRobot;

  beforeEach(() => {
    mockClipboard = {
      readText: vi.fn().mockReturnValue('original clipboard'),
      writeText: vi.fn(),
    };
    mockRobot = {
      keyTap: vi.fn(),
    };
  });

  it('writes text to clipboard', async () => {
    await pasteText('hello world', { autoPaste: false, restoreDelay: 0, clipboard: mockClipboard });
    expect(mockClipboard.writeText).toHaveBeenCalledWith('hello world');
  });

  it('preserves original clipboard when auto-pasting', async () => {
    await pasteText('hello world', { autoPaste: true, restoreDelay: 10, clipboard: mockClipboard, robot: mockRobot });
    // First call writes new text
    const calls = mockClipboard.writeText.mock.calls;
    expect(calls[0][0]).toBe('hello world');
    // After delay, original should be restored
    await new Promise((r) => setTimeout(r, 100));
    expect(calls[calls.length - 1][0]).toBe('original clipboard');
  });

  it('throws when clipboard is not available', async () => {
    await expect(pasteText('hello', { clipboard: null, robot: null }))
      .rejects.toThrow('Electron clipboard not available');
  });

  it('writes to clipboard but skips paste when robot is null', async () => {
    await pasteText('hello', { autoPaste: true, restoreDelay: 0, clipboard: mockClipboard, robot: null });
    expect(mockClipboard.writeText).toHaveBeenCalledWith('hello');
    // readText should still be called to save original
    expect(mockClipboard.readText).toHaveBeenCalled();
  });

  it('simulates Ctrl+V when auto-pasting', async () => {
    await pasteText('test', { autoPaste: true, restoreDelay: 10, clipboard: mockClipboard, robot: mockRobot });
    expect(mockRobot.keyTap).toHaveBeenCalledWith('v', 'control');
  });
});
