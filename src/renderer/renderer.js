const statusBadge = document.getElementById('status-badge');
const transcriptionText = document.getElementById('transcription-text');
const downloadSection = document.getElementById('download-section');
const progressFill = document.getElementById('progress-fill');
const progressText = document.getElementById('progress-text');
const dictEntries = document.getElementById('dict-entries');
const dictKeyInput = document.getElementById('dict-key');
const dictValueInput = document.getElementById('dict-value');
const dictAddBtn = document.getElementById('dict-add-btn');
const permissionSection = document.getElementById('permission-section');

// Audio capture instance
let audioCapture = new AudioCapture();

// Tabs
document.querySelectorAll('.tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach((t) => t.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach((c) => c.classList.remove('active'));
    tab.classList.add('active');
    document.getElementById(`${tab.dataset.tab}-tab`).classList.add('active');
  });
});

// Status updates
window.openvoice.onStatusChange((status) => {
  statusBadge.textContent = status;
  statusBadge.className = '';

  if (status === 'recording') statusBadge.classList.add('status-recording');
  else if (status === 'transcribing') statusBadge.classList.add('status-transcribing');
  else if (status.includes('download')) statusBadge.classList.add('status-downloading');
  else statusBadge.classList.add('status-idle');

  downloadSection.classList.toggle('hidden', !status.includes('download'));
});

// Recording control from main process
window.openvoice.onStartRecording(async () => {
  await audioCapture.start();
});

window.openvoice.onStopRecording(() => {
  const pcmData = audioCapture.stop();
  window.openvoice.sendAudioData(pcmData);
});

// Transcription display
window.openvoice.onTranscription((text) => {
  transcriptionText.textContent = text || '(empty)';
});

window.openvoice.onTranscriptionError((error) => {
  transcriptionText.textContent = `Error: ${error}`;
});

// Download progress
window.openvoice.onDownloadProgress((progress) => {
  progressFill.style.width = `${progress.percent}%`;
  const mb = (progress.downloaded / 1024 / 1024).toFixed(0);
  const totalMb = (progress.total / 1024 / 1024).toFixed(0);
  progressText.textContent = `${mb} / ${totalMb} MB (${progress.percent}%)`;
});

// Permission warning (macOS)
window.openvoice.onPermissionRequired((permission) => {
  if (permission === 'accessibility') {
    permissionSection.classList.remove('hidden');
  }
});

// Dictionary
let dictionary = {};

async function loadDictionary() {
  dictionary = await window.openvoice.getDictionary();
  renderDictionary();
}

function renderDictionary() {
  dictEntries.innerHTML = '';
  for (const [key, value] of Object.entries(dictionary)) {
    const row = document.createElement('div');
    row.className = 'dict-row';
    row.innerHTML = `
      <span class="key">${key}</span>
      <span class="arrow">&rarr;</span>
      <span class="value">${value}</span>
      <button data-key="${key}">&times;</button>
    `;
    row.querySelector('button').addEventListener('click', () => deleteDictEntry(key));
    dictEntries.appendChild(row);
  }
}

function deleteDictEntry(key) {
  delete dictionary[key];
  window.openvoice.setDictionary(dictionary);
  renderDictionary();
}

dictAddBtn.addEventListener('click', () => {
  const key = dictKeyInput.value.trim().toLowerCase();
  const value = dictValueInput.value.trim();
  if (!key || !value) return;

  dictionary[key] = value;
  window.openvoice.setDictionary(dictionary);
  dictKeyInput.value = '';
  dictValueInput.value = '';
  renderDictionary();
});

// Settings
async function loadSettings() {
  const settings = await window.openvoice.getSettings();
  document.getElementById('setting-hotkey').value = settings.hotkey;
  document.getElementById('setting-autopaste').checked = settings.autoPaste;
  document.getElementById('setting-startup').checked = settings.startAtLogin;
}

document.getElementById('setting-autopaste').addEventListener('change', (e) => {
  window.openvoice.setSetting('autoPaste', e.target.checked);
});

document.getElementById('setting-startup').addEventListener('change', (e) => {
  window.openvoice.setSetting('startAtLogin', e.target.checked);
});

// Init
loadDictionary();
loadSettings();
