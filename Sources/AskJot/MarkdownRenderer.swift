import SwiftUI

/// Lightweight markdown preprocessor + renderer for Ask Jot answers.
/// Safe to run on streaming snapshots.
enum ChatMarkdown {
    private static let editorialBulletPrefix = "\u{2014}\u{2002}"

    static func render(_ raw: String, streaming: Bool) -> AttributedString {
        let preprocessed = preprocess(raw, streaming: streaming)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = true
        options.failurePolicy = .returnPartiallyParsedIfPossible

        var rendered = (try? AttributedString(markdown: preprocessed, options: options))
            ?? AttributedString(preprocessed)

        for run in rendered.runs {
            let intent = run.inlinePresentationIntent
            if intent?.contains(.code) == true {
                rendered[run.range].font = .system(size: AskJotType.monoSize, weight: .medium, design: .monospaced)
            } else if intent?.contains(.stronglyEmphasized) == true {
                rendered[run.range].font = .system(size: AskJotType.bodySize, weight: .semibold, design: .serif)
            } else {
                rendered[run.range].font = .system(size: AskJotType.bodySize, weight: .regular, design: .serif)
            }
        }

        return rendered
    }

    private static func preprocess(_ text: String, streaming: Bool) -> String {
        var lines = normalizedLines(in: text).map { line -> String in
            if let match = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let body = line[match.upperBound...].trimmingCharacters(in: .whitespaces)
                return body.isEmpty ? "" : "**\(body)**"
            }

            if let normalized = normalizeListMarker(in: line) {
                return normalized
            }

            if line.trimmingCharacters(in: .whitespaces).range(
                of: #"^([-*_])\1{2,}$"#,
                options: .regularExpression
            ) != nil {
                return ""
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                return ""
            }

            return line.trimmingCharacters(in: .whitespaces)
        }

        lines = mergeStandaloneRunInHeadings(in: lines)
        lines = collapseBlankLines(in: lines)
        lines = lines.map { applyRunInHeading($0) }

        var joined = lines.joined(separator: "\n")
        if streaming {
            joined = trimUnclosedMarkers(joined)
        }
        return joined
    }

    /// Editorial run-in: insert an en-space separator between a short
    /// bold label and the prose that follows. NO colon — in serif
    /// typography, the weight change carries the label/body distinction
    /// on its own, and a colon inside bold reads as cluttered.
    /// Idempotent via the existing `\s+` collapse; em-space is invisible
    /// to the regex once inserted.
    private static func applyRunInHeading(_ line: String) -> String {
        let pattern = #"^(\s*(?:(?:\u{2014}\u{2002})|(?:\d+[.)]\s+)|(?:[A-Za-z][.)]\s+))?)\*\*([^*\n\[\]]{2,30})\*\*\s+(\S)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        let range = NSRange(line.startIndex..., in: line)
        return regex.stringByReplacingMatches(
            in: line,
            range: range,
            withTemplate: "$1**$2**\u{2002}$3"
        )
    }

    private static func normalizedLines(in text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func normalizeListMarker(in line: String) -> String? {
        if let match = match(
            #"^(\s*)([-*])\s+(.+?)\s*$"#,
            in: line
        ) {
            let body = match[3].trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return "" }
            return match[1] + editorialBulletPrefix + body
        }

        if let match = match(
            #"^(\s*)((?:\d+|[A-Za-z])[.)])\s+(.+?)\s*$"#,
            in: line
        ) {
            let body = match[3].trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return "" }
            return match[1] + match[2] + " " + body
        }

        return nil
    }

    private static func mergeStandaloneRunInHeadings(in lines: [String]) -> [String] {
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            guard isStandaloneRunInHeading(line),
                  let next = nextNonEmptyIndex(after: index, in: lines),
                  !isStandaloneRunInHeading(lines[next]),
                  !isListLine(lines[next])
            else {
                output.append(line)
                index += 1
                continue
            }

            output.append(line.trimmingCharacters(in: .whitespaces) + " " + lines[next].trimmingCharacters(in: .whitespaces))
            index = next + 1
        }

        return output
    }

    private static func collapseBlankLines(in lines: [String]) -> [String] {
        var output: [String] = []
        var previousBlank = true

        for line in lines {
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if blank {
                if previousBlank { continue }
                output.append("")
            } else {
                output.append(line)
            }
            previousBlank = blank
        }

        while output.last?.isEmpty == true {
            output.removeLast()
        }
        return output
    }

    private static func isEditorialListLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(editorialBulletPrefix)
    }

    private static func isOrderedListLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).range(
            of: #"^(?:\d+|[A-Za-z])[.)]\s+"#,
            options: .regularExpression
        ) != nil
    }

    private static func isListLine(_ line: String) -> Bool {
        isEditorialListLine(line) || isOrderedListLine(line)
    }

    private static func isStandaloneRunInHeading(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).range(
            of: #"^\*\*[^*\n\[\]]{2,30}\*\*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func nextNonEmptyIndex(after index: Int, in lines: [String]) -> Int? {
        var cursor = index + 1
        while cursor < lines.count {
            if !lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    private static func match(_ pattern: String, in line: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let result = regex.firstMatch(in: line, range: range) else { return nil }

        return (0..<result.numberOfRanges).compactMap { index in
            guard let range = Range(result.range(at: index), in: line) else { return nil }
            return String(line[range])
        }
    }

    private static func trimUnclosedMarkers(_ text: String) -> String {
        guard let lastNewline = text.lastIndex(of: "\n") else {
            return trimTail(text)
        }

        let head = text[..<lastNewline]
        let tail = trimTail(String(text[text.index(after: lastNewline)...]))
        return String(head) + "\n" + tail
    }

    private static func trimTail(_ line: String) -> String {
        var output = line

        let boldCount = output.components(separatedBy: "**").count - 1
        if boldCount % 2 == 1, let last = output.range(of: "**", options: .backwards) {
            output.removeSubrange(last)
        }

        let tickCount = output.filter { $0 == "`" }.count
        if tickCount % 2 == 1, let last = output.range(of: "`", options: .backwards) {
            output.removeSubrange(last)
        }

        return output
    }
}
