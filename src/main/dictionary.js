function escapeRegExp(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function applyDictionary(text, dictionary) {
  if (!text || !dictionary) return text;

  let result = text;
  for (const [key, value] of Object.entries(dictionary)) {
    const escaped = escapeRegExp(key);
    const regex = new RegExp(`\\b${escaped}\\b`, 'gi');
    result = result.replace(regex, value);
  }
  return result;
}

module.exports = { applyDictionary };
