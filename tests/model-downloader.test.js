import { describe, it, expect } from 'vitest';
import path from 'path';
import { getModelUrl, getModelPath, downloadModel } from '../src/main/model-downloader.js';

describe('model-downloader', () => {
  it('returns correct Hugging Face URL for distil-large-v3.5', () => {
    const url = getModelUrl('ggml-distil-large-v3.5.bin');
    expect(url).toBe(
      'https://huggingface.co/distil-whisper/distil-large-v3.5-ggml/resolve/main/ggml-model.bin'
    );
  });

  it('returns undefined for unknown model name', () => {
    expect(getModelUrl('nonexistent-model.bin')).toBeUndefined();
  });

  it('returns model path under provided base dir', () => {
    const p = getModelPath('/fake/appdata', 'ggml-distil-large-v3.5.bin');
    expect(p).toBe(path.resolve('/fake/appdata', 'models', 'ggml-distil-large-v3.5.bin'));
  });

  it('rejects path traversal in model name', () => {
    expect(() => getModelPath('/fake/appdata', '../etc/passwd')).toThrow('Invalid model name');
    expect(() => getModelPath('/fake/appdata', 'foo/bar.bin')).toThrow('Invalid model name');
    expect(() => getModelPath('/fake/appdata', 'foo\\bar.bin')).toThrow('Invalid model name');
  });

  it('rejects downloadModel for unknown model name', async () => {
    await expect(downloadModel('/tmp', 'unknown.bin', () => {}))
      .rejects.toThrow('Unknown model: unknown.bin');
  });
});
