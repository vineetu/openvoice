// DOM refs — main app
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

// DOM refs — setup screen
const setupScreen = document.getElementById('setup-screen');
const appContainer = document.getElementById('app');
const setupFolderPath = document.getElementById('setup-folder-path');
const setupBrowseBtn = document.getElementById('setup-browse-btn');
const setupDownloadBtn = document.getElementById('setup-download-btn');
const setupProgress = document.getElementById('setup-progress');
const setupProgressFill = document.getElementById('setup-progress-fill');
const setupProgressText = document.getElementById('setup-progress-text');
const setupProgressSize = document.getElementById('setup-progress-size');
const setupLoading = document.getElementById('setup-loading');
const setupError = document.getElementById('setup-error');

// ---- Sidebar navigation ----
document.querySelectorAll('.nav-item').forEach((item) => {
  item.addEventListener('click', () => {
    document.querySelectorAll('.nav-item').forEach((n) => n.classList.remove('active'));
    document.querySelectorAll('.view').forEach((v) => v.classList.remove('active'));
    item.classList.add('active');
    document.getElementById(`view-${item.dataset.view}`).classList.add('active');
  });
});

// ---- Setup screen state ----
let setupVisible = false;
let selectedFolder = null; // null = use default AppData

function showSetupScreen() {
  setupVisible = true;
  setupScreen.classList.remove('hidden');
  appContainer.classList.add('hidden');
}

function hideSetupScreen() {
  setupVisible = false;
  setupScreen.classList.add('hidden');
  appContainer.classList.remove('hidden');
}

// ---- Status updates ----
const STATUS_MAP = {
  idle: { label: 'Ready to listen', mini: 'Ready', bodyClass: '' },
  recording: { label: 'Listening...', mini: 'Recording', bodyClass: 'recording' },
  transcribing: { label: 'Transcribing...', mini: 'Processing', bodyClass: 'transcribing' },
  'downloading model': { label: 'Downloading model...', mini: 'Downloading', bodyClass: '' },
  'loading model': { label: 'Loading model...', mini: 'Loading', bodyClass: '' },
  'needs-setup': { label: 'Setup required', mini: 'Setup', bodyClass: '' },
};

function setUIStatus(status) {
  document.body.classList.remove('recording', 'transcribing', 'error');

  // Handle setup screen visibility
  if (status === 'needs-setup') {
    showSetupScreen();
    return;
  }

  // When transitioning to idle and setup is visible, hide setup screen
  if (status === 'idle' && setupVisible) {
    hideSetupScreen();
  }

  // During setup, keep the main app download section hidden and
  // handle downloading/loading states entirely within the setup screen
  if (status === 'downloading model' && setupVisible) {
    return;
  }
  if (status === 'loading model' && setupVisible) {
    setupLoading.classList.remove('hidden');
    setupProgress.classList.add('hidden');
    return;
  }

  if (status.startsWith('error:')) {
    document.body.classList.add('error');
    const msg = status.replace(/^error:\s*/, '');
    if (setupVisible) {
      setupError.textContent = msg || 'Unknown error';
      setupError.classList.remove('hidden');
      setupDownloadBtn.classList.remove('hidden');
      setupProgress.classList.add('hidden');
      setupLoading.classList.add('hidden');
      return;
    }
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
  const pct = `${progress.percent}%`;
  const mb = (progress.downloaded / 1024 / 1024).toFixed(0);
  const totalMb = (progress.total / 1024 / 1024).toFixed(0);
  const sizeText = `${mb} / ${totalMb} MB`;

  // Update main app progress (home view)
  progressFill.style.width = pct;
  progressText.textContent = pct;
  progressSize.textContent = sizeText;

  // Update setup screen progress
  setupProgressFill.style.width = pct;
  setupProgressText.textContent = pct;
  setupProgressSize.textContent = sizeText;
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

    const keySpan = document.createElement('span');
    keySpan.className = 'key';
    keySpan.textContent = key;

    const arrowSpan = document.createElement('span');
    arrowSpan.className = 'arrow';
    arrowSpan.innerHTML = '&rarr;';

    const valueSpan = document.createElement('span');
    valueSpan.className = 'value';
    valueSpan.textContent = value;

    const deleteBtn = document.createElement('button');
    deleteBtn.className = 'delete-btn';
    deleteBtn.textContent = '\u00D7';
    deleteBtn.addEventListener('click', () => deleteDictEntry(key));

    row.append(keySpan, arrowSpan, valueSpan, deleteBtn);
    dictEntries.appendChild(row);
  }
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

// ---- Setup screen actions ----
setupBrowseBtn.addEventListener('click', async () => {
  const folder = await window.openvoice.pickModelFolder();
  if (folder) {
    selectedFolder = folder;
    setupFolderPath.value = folder;
  }
});

setupDownloadBtn.addEventListener('click', async () => {
  setupDownloadBtn.classList.add('hidden');
  setupError.classList.add('hidden');
  setupProgress.classList.remove('hidden');
  try {
    await window.openvoice.startDownload(selectedFolder);
  } catch (err) {
    setupError.textContent = err.message || 'Download failed';
    setupError.classList.remove('hidden');
    setupDownloadBtn.classList.remove('hidden');
    setupProgress.classList.add('hidden');
    setupLoading.classList.add('hidden');
  }
});

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

// ---- Hotkey capture ----
const hotkeyInput = document.getElementById('setting-hotkey');
const hotkeyError = document.getElementById('hotkey-error');
let hotkeyCapturing = false;
let hotkeyPrevious = '';

// Map browser key names to Electron accelerator format
function keyEventToAccelerator(e) {
  const parts = [];
  if (e.ctrlKey) parts.push('Ctrl');
  if (e.altKey) parts.push('Alt');
  if (e.shiftKey) parts.push('Shift');
  if (e.metaKey) parts.push('Super');

  const key = e.key;
  // Ignore standalone modifier presses
  if (['Control', 'Alt', 'Shift', 'Meta'].includes(key)) return null;

  // Must have at least one modifier
  if (parts.length === 0) return null;

  // Map key to Electron format
  if (/^F\d{1,2}$/.test(key)) {
    parts.push(key); // F1-F12
  } else if (key === ' ') {
    parts.push('Space');
  } else if (/^[a-zA-Z]$/.test(key)) {
    parts.push(key.toUpperCase());
  } else if (/^[0-9]$/.test(key)) {
    parts.push(key);
  } else {
    return null; // Unsupported key
  }

  return parts.join('+');
}

function showModifiersPreview(e) {
  const parts = [];
  if (e.ctrlKey) parts.push('Ctrl');
  if (e.altKey) parts.push('Alt');
  if (e.shiftKey) parts.push('Shift');
  if (e.metaKey) parts.push('Super');
  if (parts.length > 0) {
    hotkeyInput.value = parts.join('+') + '+...';
  }
}

hotkeyInput.addEventListener('click', () => {
  if (hotkeyCapturing) return;
  hotkeyCapturing = true;
  hotkeyPrevious = hotkeyInput.value;
  hotkeyInput.value = 'Press a key combo...';
  hotkeyInput.classList.add('capturing');
  hotkeyError.textContent = '';
  hotkeyError.classList.remove('visible');
});

hotkeyInput.addEventListener('keydown', (e) => {
  if (!hotkeyCapturing) return;
  e.preventDefault();
  e.stopPropagation();

  // Escape cancels capture
  if (e.key === 'Escape') {
    hotkeyCapturing = false;
    hotkeyInput.value = hotkeyPrevious;
    hotkeyInput.classList.remove('capturing');
    return;
  }

  // Show live modifier preview
  const accelerator = keyEventToAccelerator(e);
  if (!accelerator) {
    showModifiersPreview(e);
    return;
  }

  // Got a valid combo — try to save
  hotkeyInput.value = accelerator;
  hotkeyCapturing = false;
  hotkeyInput.classList.remove('capturing');

  window.openvoice.setSetting('hotkey', accelerator).then(() => {
    hotkeyPrevious = accelerator;
    hotkeyError.textContent = '';
    hotkeyError.classList.remove('visible');
  }).catch((err) => {
    hotkeyError.textContent = err.message || 'Invalid hotkey';
    hotkeyError.classList.add('visible');
    hotkeyInput.value = hotkeyPrevious;
  });
});

hotkeyInput.addEventListener('blur', () => {
  if (hotkeyCapturing) {
    hotkeyCapturing = false;
    hotkeyInput.value = hotkeyPrevious;
    hotkeyInput.classList.remove('capturing');
  }
});

// ---- Init ----
loadDictionary();
loadSettings();

// Check initial status to handle race condition (status may have been
// set before renderer listeners were attached)
window.openvoice.getStatus().then((status) => {
  setUIStatus(status);
});
