class PCMProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.bufferSize = 4096;
    this.buffer = new Float32Array(this.bufferSize);
    this.bufferIndex = 0;
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || !input[0]) return true;

    const channelData = input[0];

    for (let i = 0; i < channelData.length; i++) {
      this.buffer[this.bufferIndex++] = channelData[i];

      if (this.bufferIndex >= this.bufferSize) {
        // Send buffer to main thread
        this.port.postMessage({
          type: 'pcm',
          data: this.buffer.slice(),
        });
        this.bufferIndex = 0;
      }
    }

    return true;
  }
}

registerProcessor('pcm-processor', PCMProcessor);
