const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');

const MODEL_URLS = {
  'ggml-distil-large-v3.5.bin':
    'https://huggingface.co/distil-whisper/distil-large-v3.5-ggml/resolve/main/ggml-model.bin',
};

function getModelUrl(modelName) {
  return MODEL_URLS[modelName];
}

function getModelPath(baseDir, modelName) {
  return path.join(baseDir, 'models', modelName);
}

function modelExists(baseDir, modelName) {
  return fs.existsSync(getModelPath(baseDir, modelName));
}

/**
 * Downloads a model file with progress reporting.
 * @param {string} baseDir - App data directory
 * @param {string} modelName - Model filename
 * @param {function} onProgress - Called with { downloaded, total, percent }
 * @returns {Promise<string>} Path to downloaded model
 */
function downloadModel(baseDir, modelName, onProgress) {
  return new Promise((resolve, reject) => {
    const url = getModelUrl(modelName);
    if (!url) return reject(new Error(`Unknown model: ${modelName}`));

    const modelPath = getModelPath(baseDir, modelName);
    const modelDir = path.dirname(modelPath);

    if (!fs.existsSync(modelDir)) {
      fs.mkdirSync(modelDir, { recursive: true });
    }

    const file = fs.createWriteStream(modelPath);

    const MAX_REDIRECTS = 10;

    function followRedirects(requestUrl, redirectCount = 0) {
      if (redirectCount > MAX_REDIRECTS) {
        reject(new Error('Too many redirects'));
        return;
      }

      const client = requestUrl.startsWith('https') ? https : http;
      client.get(requestUrl, (response) => {
        if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
          followRedirects(response.headers.location, redirectCount + 1);
          return;
        }

        if (response.statusCode !== 200) {
          try { fs.unlinkSync(modelPath); } catch {}
          reject(new Error(`Download failed: HTTP ${response.statusCode}`));
          return;
        }

        const total = parseInt(response.headers['content-length'], 10) || 0;
        let downloaded = 0;

        response.on('data', (chunk) => {
          downloaded += chunk.length;
          if (onProgress && total > 0) {
            onProgress({
              downloaded,
              total,
              percent: Math.round((downloaded / total) * 100),
            });
          }
        });

        response.pipe(file);

        response.on('error', (err) => {
          file.destroy();
          try { fs.unlinkSync(modelPath); } catch {}
          reject(err);
        });

        file.on('finish', () => {
          file.close();
          resolve(modelPath);
        });

        file.on('error', (err) => {
          try { fs.unlinkSync(modelPath); } catch {}
          reject(err);
        });
      }).on('error', (err) => {
        try { fs.unlinkSync(modelPath); } catch {}
        reject(err);
      });
    }

    followRedirects(url);
  });
}

module.exports = { getModelUrl, getModelPath, modelExists, downloadModel };
