const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');
const { DEFAULTS } = require('./settings');

function getModelUrl() {
  return DEFAULTS.modelUrl;
}

function getModelPath(baseDir) {
  return path.join(baseDir, 'models', DEFAULTS.modelName);
}

function modelExists(baseDir) {
  return fs.existsSync(getModelPath(baseDir));
}

/**
 * Get file size for resume support
 */
function getPartialSize(filePath) {
  const partialPath = filePath + '.partial';
  try {
    const stats = fs.statSync(partialPath);
    return stats.size;
  } catch {
    return 0;
  }
}

/**
 * Downloads a model file with progress reporting and resume support.
 * @param {string} baseDir - App data directory
 * @param {function} onProgress - Called with { downloaded, total, percent }
 * @returns {Promise<string>} Path to downloaded model
 */
function downloadModel(baseDir, onProgress) {
  return new Promise((resolve, reject) => {
    const url = getModelUrl();
    const modelPath = getModelPath(baseDir);
    const partialPath = modelPath + '.partial';
    const modelDir = path.dirname(modelPath);

    if (!fs.existsSync(modelDir)) {
      fs.mkdirSync(modelDir, { recursive: true });
    }

    const existingSize = getPartialSize(modelPath);

    function followRedirects(requestUrl, redirectCount = 0) {
      if (redirectCount > 10) {
        reject(new Error('Too many redirects'));
        return;
      }

      const client = requestUrl.startsWith('https') ? https : http;
      const headers = existingSize > 0 ? { Range: `bytes=${existingSize}-` } : {};

      const req = client.get(requestUrl, { headers }, (response) => {
        // Handle redirects
        if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
          followRedirects(response.headers.location, redirectCount + 1);
          return;
        }

        // Handle resume (206) or fresh download (200)
        if (response.statusCode !== 200 && response.statusCode !== 206) {
          reject(new Error(`Download failed: HTTP ${response.statusCode}`));
          return;
        }

        const isResume = response.statusCode === 206;
        const contentLength = parseInt(response.headers['content-length'], 10) || 0;
        const total = isResume ? existingSize + contentLength : contentLength;

        const file = fs.createWriteStream(partialPath, {
          flags: isResume ? 'a' : 'w',
        });

        let downloaded = isResume ? existingSize : 0;

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

        file.on('finish', () => {
          file.close();
          // Rename partial to final
          fs.renameSync(partialPath, modelPath);
          resolve(modelPath);
        });

        file.on('error', (err) => {
          // Don't delete partial file — allows resume
          reject(err);
        });
      });

      req.on('error', (err) => {
        reject(err);
      });
    }

    followRedirects(url);
  });
}

module.exports = { getModelUrl, getModelPath, modelExists, downloadModel };
