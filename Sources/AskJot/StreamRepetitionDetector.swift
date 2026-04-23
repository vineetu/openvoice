import Foundation

/// Client-side safety net because Apple's public `GenerationOptions` does not expose a repetition penalty, and on-device 3B models are known to loop on list-style or enumeration prompts.
struct StreamRepetitionDetector {
    private static let ngramSize = 6
    private static let repetitionThreshold = 3
    private static let maxWords = 200
    private static let maxTrackedNgrams = maxWords - ngramSize + 1

    private var lastObservedText = ""
    private var trailingFragment = ""

    private var words: [String] = []
    private var wordStartIndex = 0

    private var ngrams: [String] = []
    private var ngramStartIndex = 0

    private var ngramCounts: [String: Int] = [:]
    private var repeatedNgrams: Set<String> = []

    mutating func observe(fullText: String) {
        let delta: String
        if fullText.hasPrefix(lastObservedText) {
            delta = String(fullText.dropFirst(lastObservedText.count))
        } else {
            resetRollingState()
            delta = fullText
        }
        lastObservedText = fullText
        append(deltaText: delta)
    }

    mutating func append(deltaText: String) {
        guard !deltaText.isEmpty else { return }

        let text = trailingFragment + deltaText
        let endsInsideWord = text.unicodeScalars.last.map(Self.isWordScalar(_:)) ?? false
        let tokens = Self.wordTokens(in: text)

        if endsInsideWord, let trailing = tokens.last {
            trailingFragment = trailing
            for word in tokens.dropLast() {
                append(word: word)
            }
            return
        }

        trailingFragment = ""
        for word in tokens {
            append(word: word)
        }
    }

    func isLooping() -> Bool {
        !repeatedNgrams.isEmpty
    }

    private mutating func append(word: String) {
        guard !word.isEmpty else { return }

        words.append(word)
        if activeWordCount >= Self.ngramSize {
            let key = words.suffix(Self.ngramSize).joined(separator: " ")
            ngrams.append(key)

            let oldCount = ngramCounts[key, default: 0]
            let newCount = oldCount + 1
            ngramCounts[key] = newCount
            if newCount >= Self.repetitionThreshold {
                repeatedNgrams.insert(key)
            }
        }

        if activeWordCount > Self.maxWords {
            wordStartIndex += 1
            removeOldestNgramIfNeeded()
        }

        compactBuffersIfNeeded()
    }

    private mutating func removeOldestNgramIfNeeded() {
        guard activeNgramCount > Self.maxTrackedNgrams else { return }
        let key = ngrams[ngramStartIndex]
        ngramStartIndex += 1

        guard let oldCount = ngramCounts[key] else { return }
        let newCount = oldCount - 1
        if oldCount == Self.repetitionThreshold {
            repeatedNgrams.remove(key)
        }
        if newCount == 0 {
            ngramCounts.removeValue(forKey: key)
        } else {
            ngramCounts[key] = newCount
        }
    }

    private mutating func compactBuffersIfNeeded() {
        if wordStartIndex >= Self.maxWords {
            words.removeFirst(wordStartIndex)
            wordStartIndex = 0
        }
        if ngramStartIndex >= Self.maxTrackedNgrams {
            ngrams.removeFirst(ngramStartIndex)
            ngramStartIndex = 0
        }
    }

    private mutating func resetRollingState() {
        trailingFragment = ""
        words.removeAll(keepingCapacity: true)
        wordStartIndex = 0
        ngrams.removeAll(keepingCapacity: true)
        ngramStartIndex = 0
        ngramCounts.removeAll(keepingCapacity: true)
        repeatedNgrams.removeAll(keepingCapacity: true)
    }

    private var activeWordCount: Int {
        words.count - wordStartIndex
    }

    private var activeNgramCount: Int {
        ngrams.count - ngramStartIndex
    }

    private static func wordTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        current.reserveCapacity(16)

        for scalar in text.unicodeScalars {
            if isWordScalar(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current.lowercased())
                current.removeAll(keepingCapacity: true)
            }
        }

        if !current.isEmpty {
            tokens.append(current.lowercased())
        }

        return tokens
    }

    private static func isWordScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
    }
}
