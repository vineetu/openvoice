function escapeRegExp(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function applyDictionary(text, dictionary) {
  if (!text || !dictionary) return text;

  let result = text;
  for (const [key, value] of Object.entries(dictionary)) {
    const escaped = escapeRegExp(key);
    // Use \b for word-char boundaries, lookaround for non-word-char boundaries
    const prefix = /^\w/.test(key) ? '\\b' : '(?<=\\W|^)';
    const suffix = /\w$/.test(key) ? '\\b' : '(?=\\W|$)';
    const regex = new RegExp(`${prefix}${escaped}${suffix}`, 'gi');
    result = result.replace(regex, value);
  }
  return result;
}

module.exports = { applyDictionary };
