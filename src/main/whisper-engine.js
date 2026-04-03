// Try to load WASM-based whisper first (cross-platform)
// Fall back to native addon if available
let whisperWasm;
let whisperNative;

try {
  whisperWasm = require('@nicepkg/whisper.cpp.wasm');
} catch {
  whisperWasm = null;
}

try {
  whisperNative = require('@kutalia/whisper-node-addon').default;
} catch {
  whisperNative = null;
}

class WhisperEngine {
  constructor(modelPath) {
    this.modelPath = modelPath;
    this.whisperInstance = null;
    this.useWasm = !!whisperWasm;
  }

  async init() {
    if (whisperWasm) {
      // WASM version needs to be initialized with model
      this.whisperInstance = await whisperWasm.createWhisper(this.modelPath);
      this.useWasm = true;
    } else if (whisperNative) {
      // Native addon doesn't need init - model path passed per call
      this.useWasm = false;
    } else {
      throw new Error('No Whisper engine available. Install @nicepkg/whisper.cpp.wasm or @kutalia/whisper-node-addon');
    }
  }

  /**
   * Transcribe audio from Float32Array PCM data.
   * @param {Float32Array} pcmf32 - 16kHz mono audio
   * @returns {Promise<string>} Transcribed text
   */
  async transcribe(pcmf32) {
    if (this.useWasm && this.whisperInstance) {
      // WASM API
      const result = await this.whisperInstance.transcribe(pcmf32, {
        language: 'en',
      });
      return result.text || '';
    } else if (whisperNative) {
      // Native addon API
      const result = await whisperNative.transcribe({
        pcmf32,
        model: this.modelPath,
        language: 'en',
        use_gpu: true,
        no_timestamps: true,
      });

      if (!result || !result.transcription || result.transcription.length === 0) {
        return '';
      }

      // Each segment is [startTime, endTime, text]
      return result.transcription.map((seg) => seg[2]).join(' ').trim();
    }

    throw new Error('No Whisper engine available');
  }
}

module.exports = { WhisperEngine };
