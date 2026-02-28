import { describe, it, expect, vi, beforeEach } from 'vitest';
import { AudioCapture } from '../src/main/audio-capture.js';

describe('AudioCapture', () => {
  let capture;
  let mockRecord;

  beforeEach(() => {
    vi.spyOn(AudioCapture, 'checkSoxAvailable').mockReturnValue(true);
    const mockStream = {
      on: vi.fn().mockReturnThis(),
      pipe: vi.fn().mockReturnThis(),
    };
    mockRecord = {
      record: vi.fn().mockReturnValue({
        stream: () => mockStream,
        stop: vi.fn(),
      }),
    };
    capture = new AudioCapture(mockRecord);
  });

  it('starts not recording', () => {
    expect(capture.isRecording()).toBe(false);
  });

  it('has a temp file path after construction', () => {
    expect(capture.getTempFilePath()).toMatch(/\.wav$/);
  });

  it('sets recording state on start', () => {
    capture.start();
    expect(capture.isRecording()).toBe(true);
    expect(mockRecord.record).toHaveBeenCalledWith({
      sampleRate: 16000,
      channels: 1,
      audioType: 'raw',
      recorder: 'sox',
    });
  });

  it('stop without start resolves with temp path', async () => {
    const path = await capture.stop();
    expect(path).toMatch(/\.wav$/);
    expect(capture.isRecording()).toBe(false);
  });

  it('does not start twice if already recording', () => {
    capture.start();
    capture.start(); // second call should be no-op
    expect(mockRecord.record).toHaveBeenCalledTimes(1);
  });

  it('throws if record module is not available', () => {
    const captureNoModule = new AudioCapture(null);
    expect(() => captureNoModule.start()).toThrow('node-record-lpcm16 not available');
  });

  it('throws if SoX is not found on PATH', () => {
    AudioCapture.checkSoxAvailable.mockReturnValue(false);
    expect(() => capture.start()).toThrow('SoX not found');
  });
});
