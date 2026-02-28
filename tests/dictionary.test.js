import { describe, it, expect } from 'vitest';
import { applyDictionary } from '../src/main/dictionary.js';

describe('applyDictionary', () => {
  it('returns text unchanged when dictionary is empty', () => {
    expect(applyDictionary('hello world', {})).toBe('hello world');
  });

  it('replaces a single word match', () => {
    const dict = { btw: 'by the way' };
    expect(applyDictionary('btw that was great', dict)).toBe('by the way that was great');
  });

  it('replaces multiple different words', () => {
    const dict = { btw: 'by the way', addr: '123 Main Street' };
    expect(applyDictionary('btw my addr is here', dict)).toBe('by the way my 123 Main Street is here');
  });

  it('only replaces whole words (word boundary)', () => {
    const dict = { he: 'she' };
    expect(applyDictionary('hello there he said', dict)).toBe('hello there she said');
  });

  it('is case-insensitive for matching', () => {
    const dict = { openai: 'OpenAI' };
    expect(applyDictionary('I work at openai now', dict)).toBe('I work at OpenAI now');
  });

  it('handles multiple occurrences of the same word', () => {
    const dict = { btw: 'by the way' };
    expect(applyDictionary('btw this and btw that', dict)).toBe('by the way this and by the way that');
  });

  it('returns text unchanged when no matches found', () => {
    const dict = { xyz: 'replaced' };
    expect(applyDictionary('hello world', dict)).toBe('hello world');
  });

  it('handles empty text', () => {
    expect(applyDictionary('', { btw: 'by the way' })).toBe('');
  });

  it('escapes regex special characters in dictionary keys', () => {
    const dict = { 'c++': 'C++' };
    expect(applyDictionary('I use c++ daily', dict)).toBe('I use C++ daily');
  });

  it('matches non-word-char keys adjacent to punctuation', () => {
    const dict = { 'c++': 'C Plus Plus' };
    expect(applyDictionary('I know c++.', dict)).toBe('I know C Plus Plus.');
    expect(applyDictionary('c++, Java, and Go', dict)).toBe('C Plus Plus, Java, and Go');
  });

  it('returns text unchanged for null/undefined inputs', () => {
    expect(applyDictionary(null, { a: 'b' })).toBeNull();
    expect(applyDictionary('hello', null)).toBe('hello');
    expect(applyDictionary(undefined, {})).toBeUndefined();
  });
});
