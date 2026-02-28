// DOM refs
const statusLabel = document.getElementById('status-label');
const statusMini = document.getElementById('status-text-mini');
const transcriptionText = document.getElementById('transcription-text');
const transcriptionTimestamp = document.getElementById('transcription-timestamp');
const downloadSection = document.getElementById('download-section');
const progressFill = document.getElementById('progress-fill');
const progressText = document.getElementById('progress-text');
const progressSize = document.getElementById('progress-size');
const dictEntries = document.getElementById('dict-entries');
const dictEmpty = document.getElementById('dict-empty');
const dictKeyInput = document.getElementById('dict-key');
const dictValueInput = document.getElementById('dict-value');
const dictAddBtn = document.getElementById('dict-add-btn');

// ---- Tabs ----
document.querySelectorAll('.panel-tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.panel-tab').forEach((t) => t.classList.remove('active'));
    document.querySelectorAll('.panel-content').forEach((c) => c.classList.remove('active'));
    tab.classList.add('active');
    document.getElementById(`${tab.dataset.tab}-tab`).classList.add('active');
  });
});

// ---- Status updates ----
const STATUS_MAP = {
  idle: { label: 'Ready to listen', mini: 'Ready', bodyClass: '' },
  recording: { label: 'Listening...', mini: 'Recording', bodyClass: 'recording' },
  transcribing: { label: 'Transcribing...', mini: 'Processing', bodyClass: 'transcribing' },
  'downloading model': { label: 'Downloading model...', mini: 'Downloading', bodyClass: '' },
  'loading model': { label: 'Loading model...', mini: 'Loading', bodyClass: '' },
};

function setUIStatus(status) {
  // Remove all state classes
  document.body.classList.remove('recording', 'transcribing', 'error');

  // Check for error state
  if (status.startsWith('error:')) {
    document.body.classList.add('error');
    const msg = status.replace(/^error:\s*/, '');
    statusLabel.textContent = msg || 'Unknown error';
    statusMini.textContent = 'Error';
    return;
  }

  const map = STATUS_MAP[status] || { label: status, mini: status, bodyClass: '' };
  statusLabel.textContent = map.label;
  statusMini.textContent = map.mini;

  if (map.bodyClass) {
    document.body.classList.add(map.bodyClass);
  }

  // Show/hide download section
  downloadSection.classList.toggle('hidden', !status.includes('download'));
}

window.openvoice.onStatusChange((status) => {
  setUIStatus(status);
});

// ---- Transcription display ----
window.openvoice.onTranscription((text) => {
  if (text) {
    transcriptionText.textContent = text;
    transcriptionText.classList.add('has-text');
    transcriptionTimestamp.textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  } else {
    transcriptionText.textContent = '(empty transcription)';
    transcriptionText.classList.remove('has-text');
  }
});

window.openvoice.onTranscriptionError((error) => {
  transcriptionText.textContent = error;
  transcriptionText.classList.remove('has-text');
});

// ---- Microphone permission warning ----
window.openvoice.onMicPermission((status) => {
  setUIStatus(`error: Microphone access ${status}. Enable microphone in Windows Settings > Privacy.`);
});

// ---- Download progress ----
window.openvoice.onDownloadProgress((progress) => {
  progressFill.style.width = `${progress.percent}%`;
  progressText.textContent = `${progress.percent}%`;
  const mb = (progress.downloaded / 1024 / 1024).toFixed(0);
  const totalMb = (progress.total / 1024 / 1024).toFixed(0);
  progressSize.textContent = `${mb} / ${totalMb} MB`;
});

// ---- Dictionary ----
let dictionary = {};

async function loadDictionary() {
  dictionary = await window.openvoice.getDictionary();
  renderDictionary();
}

function renderDictionary() {
  dictEntries.innerHTML = '';
  const keys = Object.keys(dictionary);

  if (keys.length === 0) {
    dictEmpty.style.display = 'flex';
    dictEntries.style.display = 'none';
    return;
  }

  dictEmpty.style.display = 'none';
  dictEntries.style.display = 'block';

  for (const [key, value] of Object.entries(dictionary)) {
    const row = document.createElement('div');
    row.className = 'dict-row';
    row.innerHTML = `
      <span class="key">${escapeHtml(key)}</span>
      <span class="arrow">&rarr;</span>
      <span class="value">${escapeHtml(value)}</span>
      <button class="delete-btn">&times;</button>
    `;
    row.querySelector('.delete-btn').addEventListener('click', () => deleteDictEntry(key));
    dictEntries.appendChild(row);
  }
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

function deleteDictEntry(key) {
  delete dictionary[key];
  window.openvoice.setDictionary(dictionary);
  renderDictionary();
}

dictAddBtn.addEventListener('click', addDictEntry);
dictKeyInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') addDictEntry(); });
dictValueInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') addDictEntry(); });

function addDictEntry() {
  const key = dictKeyInput.value.trim().toLowerCase();
  const value = dictValueInput.value.trim();
  if (!key || !value) return;

  dictionary[key] = value;
  window.openvoice.setDictionary(dictionary);
  dictKeyInput.value = '';
  dictValueInput.value = '';
  dictKeyInput.focus();
  renderDictionary();
}

// ---- Settings ----
async function loadSettings() {
  const settings = await window.openvoice.getSettings();
  document.getElementById('setting-hotkey').value = settings.hotkey;
  document.getElementById('setting-autopaste').checked = settings.autoPaste;
  document.getElementById('setting-startup').checked = settings.startWithWindows;
}

document.getElementById('setting-autopaste').addEventListener('change', (e) => {
  window.openvoice.setSetting('autoPaste', e.target.checked);
});

document.getElementById('setting-startup').addEventListener('change', (e) => {
  window.openvoice.setSetting('startWithWindows', e.target.checked);
});

// ---- Init ----
loadDictionary();
loadSettings();
