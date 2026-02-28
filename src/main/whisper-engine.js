let defaultTranscribe;
try {
  defaultTranscribe = require('@kutalia/whisper-node-addon').transcribe;
} catch {
  defaultTranscribe = null;
}

class WhisperEngine {
  constructor(transcribeFn) {
    this._transcribe = transcribeFn !== undefined ? transcribeFn : defaultTranscribe;
    this._loaded = false;
    this._modelPath = null;
  }

  isLoaded() {
    return this._loaded;
  }

  async loadModel(modelPath) {
    if (!this._transcribe) throw new Error('whisper-node-addon not available on this platform');
    this._modelPath = modelPath;
    this._loaded = true;
  }

  async transcribe(audioPath) {
    if (!this._loaded) throw new Error('Model not loaded');

    const result = await this._transcribe({
      model: this._modelPath,
      fname_inp: audioPath,
      language: 'en',
      use_gpu: true,
    });

    // Result shape: { transcription: string[][] | string[] }
    const segments = result && result.transcription;
    if (!segments || segments.length === 0) return '';
    return segments
      .map((seg) => (Array.isArray(seg) ? seg[0] : seg))
      .join(' ')
      .trim();
  }

  unload() {
    this._loaded = false;
    this._modelPath = null;
  }
}

module.exports = { WhisperEngine };
