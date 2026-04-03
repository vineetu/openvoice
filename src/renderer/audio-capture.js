class AudioCapture {
  constructor() {
    this.audioContext = null;
    this.mediaStream = null;
    this.workletNode = null;
    this.chunks = [];
    this.isRecording = false;
  }

  async start() {
    if (this.isRecording) return;

    // Request microphone access
    this.mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        sampleRate: 16000,
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
      },
    });

    // Create audio context at 16kHz
    this.audioContext = new AudioContext({ sampleRate: 16000 });

    // Load worklet
    await this.audioContext.audioWorklet.addModule('audio-worklet-processor.js');

    // Create source from microphone
    const source = this.audioContext.createMediaStreamSource(this.mediaStream);

    // Create worklet node
    this.workletNode = new AudioWorkletNode(this.audioContext, 'pcm-processor');

    // Collect PCM chunks
    this.chunks = [];
    this.workletNode.port.onmessage = (event) => {
      if (event.data.type === 'pcm') {
        this.chunks.push(event.data.data);
      }
    };

    // Connect: mic -> worklet
    source.connect(this.workletNode);

    this.isRecording = true;
  }

  stop() {
    if (!this.isRecording) return new Float32Array(0);

    // Stop all tracks
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach((track) => track.stop());
    }

    // Disconnect worklet
    if (this.workletNode) {
      this.workletNode.disconnect();
    }

    // Close audio context
    if (this.audioContext) {
      this.audioContext.close();
    }

    this.isRecording = false;

    // Concatenate all chunks into a single Float32Array
    const totalLength = this.chunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const result = new Float32Array(totalLength);
    let offset = 0;
    for (const chunk of this.chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }

    this.chunks = [];
    return result;
  }

  getIsRecording() {
    return this.isRecording;
  }
}

// Export for use in renderer
window.AudioCapture = AudioCapture;
