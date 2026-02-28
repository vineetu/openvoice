import { describe, it, expect, vi, beforeEach } from 'vitest';
import { WhisperEngine } from '../src/main/whisper-engine.js';

describe('WhisperEngine', () => {
  let engine;
  let mockTranscribe;

  beforeEach(() => {
    // Mock matches real addon API: transcribe({ model, fname_inp, ... }) => { transcription: string[][] }
    mockTranscribe = vi.fn().mockResolvedValue({
      transcription: [['hello world', '00:00:00', '00:00:02']],
    });
    engine = new WhisperEngine(mockTranscribe);
  });

  it('starts unloaded', () => {
    expect(engine.isLoaded()).toBe(false);
  });

  it('loads a model (stores path for later transcribe calls)', async () => {
    await engine.loadModel('/fake/path/model.bin');
    expect(engine.isLoaded()).toBe(true);
  });

  it('transcribes audio passing model path on each call', async () => {
    await engine.loadModel('/fake/path/model.bin');
    const text = await engine.transcribe('/fake/audio.wav');
    expect(text).toBe('hello world');
    expect(mockTranscribe).toHaveBeenCalledWith({
      model: '/fake/path/model.bin',
      fname_inp: '/fake/audio.wav',
      language: 'en',
      use_gpu: true,
    });
  });

  it('throws if transcribe called before model loaded', async () => {
    await expect(engine.transcribe('/fake/audio.wav')).rejects.toThrow('Model not loaded');
  });

  it('unloads model', async () => {
    await engine.loadModel('/fake/path/model.bin');
    engine.unload();
    expect(engine.isLoaded()).toBe(false);
  });

  it('returns empty string when transcription array is empty', async () => {
    mockTranscribe.mockResolvedValue({ transcription: [] });
    await engine.loadModel('/fake/path/model.bin');
    const text = await engine.transcribe('/fake/audio.wav');
    expect(text).toBe('');
  });

  it('returns empty string when result is null', async () => {
    mockTranscribe.mockResolvedValue(null);
    await engine.loadModel('/fake/path/model.bin');
    const text = await engine.transcribe('/fake/audio.wav');
    expect(text).toBe('');
  });

  it('handles string[] transcription format', async () => {
    mockTranscribe.mockResolvedValue({ transcription: ['hello', 'world'] });
    await engine.loadModel('/fake/path/model.bin');
    const text = await engine.transcribe('/fake/audio.wav');
    expect(text).toBe('hello world');
  });

  it('joins multiple segments from string[][] format', async () => {
    mockTranscribe.mockResolvedValue({
      transcription: [
        ['hello', '00:00:00', '00:00:01'],
        ['world', '00:00:01', '00:00:02'],
      ],
    });
    await engine.loadModel('/fake/path/model.bin');
    const text = await engine.transcribe('/fake/audio.wav');
    expect(text).toBe('hello world');
  });

  it('throws if loadModel called without whisper addon', async () => {
    const engineNoAddon = new WhisperEngine(null);
    await expect(engineNoAddon.loadModel('/fake/model.bin'))
      .rejects.toThrow('whisper-node-addon not available');
  });
});
