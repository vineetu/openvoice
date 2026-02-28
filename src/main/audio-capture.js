const path = require('path');
const os = require('os');
const fs = require('fs');
const { execFileSync } = require('child_process');

function prependBundledSoxToPath() {
  if (typeof process.resourcesPath === 'string') {
    const soxDir = path.join(process.resourcesPath, 'sox-bin');
    if (fs.existsSync(soxDir)) {
      process.env.PATH = soxDir + path.delimiter + (process.env.PATH || '');
    }
  }
}

let defaultRecord;
try {
  defaultRecord = require('node-record-lpcm16');
} catch {
  defaultRecord = null;
}

class AudioCapture {
  constructor(recordModule) {
    this._record = recordModule !== undefined ? recordModule : defaultRecord;
    this._recording = null;
    this._fileStream = null;
    this._tempPath = path.join(os.tmpdir(), `openvoice-${Date.now()}.wav`);
  }

  isRecording() {
    return this._recording !== null;
  }

  getTempFilePath() {
    return this._tempPath;
  }

  start() {
    if (!this._record) throw new Error('node-record-lpcm16 not available');
    if (this._recording) return;
    prependBundledSoxToPath();
    if (!AudioCapture.checkSoxAvailable()) {
      throw new Error(
        'SoX not found. Install SoX (sox.sourceforge.net) and ensure it is on your PATH.'
      );
    }

    this._tempPath = path.join(os.tmpdir(), `openvoice-${Date.now()}.wav`);
    this._fileStream = fs.createWriteStream(this._tempPath);

    // Write a minimal WAV header (will be updated on stop)
    this._writeWavHeader(this._fileStream, 0);

    this._recording = this._record.record({
      sampleRate: 16000,
      channels: 1,
      audioType: 'raw',
      recorder: 'sox',
    });

    this._dataSize = 0;
    this._recording.stream().on('data', (chunk) => {
      this._fileStream.write(chunk);
      this._dataSize += chunk.length;
    });
  }

  stop() {
    return new Promise((resolve) => {
      if (!this._recording) {
        resolve(this._tempPath);
        return;
      }

      this._recording.stop();
      this._recording = null;

      this._fileStream.end(() => {
        // Rewrite WAV header with correct data size
        this._updateWavHeader(this._tempPath, this._dataSize);
        resolve(this._tempPath);
      });
    });
  }

  _writeWavHeader(stream, dataSize) {
    const header = Buffer.alloc(44);
    const sampleRate = 16000;
    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * (bitsPerSample / 8);
    const blockAlign = numChannels * (bitsPerSample / 8);

    header.write('RIFF', 0);
    header.writeUInt32LE(36 + dataSize, 4);
    header.write('WAVE', 8);
    header.write('fmt ', 12);
    header.writeUInt32LE(16, 16); // PCM chunk size
    header.writeUInt16LE(1, 20); // PCM format
    header.writeUInt16LE(numChannels, 22);
    header.writeUInt32LE(sampleRate, 24);
    header.writeUInt32LE(byteRate, 28);
    header.writeUInt16LE(blockAlign, 32);
    header.writeUInt16LE(bitsPerSample, 34);
    header.write('data', 36);
    header.writeUInt32LE(dataSize, 40);

    stream.write(header);
  }

  _updateWavHeader(filePath, dataSize) {
    const fd = fs.openSync(filePath, 'r+');
    const header = Buffer.alloc(4);

    // Update RIFF chunk size
    header.writeUInt32LE(36 + dataSize, 0);
    fs.writeSync(fd, header, 0, 4, 4);

    // Update data chunk size
    header.writeUInt32LE(dataSize, 0);
    fs.writeSync(fd, header, 0, 4, 40);

    fs.closeSync(fd);
  }

  cleanup() {
    try { fs.unlinkSync(this._tempPath); } catch {}
  }

  static checkSoxAvailable() {
    try {
      execFileSync('sox', ['--version'], { stdio: 'pipe' });
      return true;
    } catch {
      return false;
    }
  }
}

module.exports = { AudioCapture };
