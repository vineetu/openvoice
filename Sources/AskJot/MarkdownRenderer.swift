import SwiftUI

/// Lightweight markdown preprocessor + renderer for Ask Jot answers.
/// Safe to run on streaming snapshots.
enum ChatMarkdown {
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
                rendered[run.range].font = .system(size: 14, weight: .medium, design: .monospaced)
            } else if intent?.contains(.stronglyEmphasized) == true {
                // Bold labels render as semibold serif — the weight
                // change is the emphasis; no colon, no color shift.
                rendered[run.range].font = .system(size: 17, weight: .semibold, design: .serif)
            } else {
                // Editorial body: New York serif 17pt regular. Larger
                // than Apple body (15pt) on purpose — long-form help
                // prose reads best at this measure on a desktop reading
                // column.
                rendered[run.range].font = .system(size: 17, weight: .regular, design: .serif)
            }
        }

        return rendered
    }

    private static func preprocess(_ text: String, streaming: Bool) -> String {
        var lines = text.components(separatedBy: "\n").map { line -> String in
            if let match = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let body = line[match.upperBound...]
                return "**\(body)**"
            }

            if let match = line.range(of: #"^\s*[-*]\s+"#, options: .regularExpression) {
                let indent = String(line[line.startIndex..<match.lowerBound])
                // Editorial bullets: em-dash + en-space instead of `•`.
                // Matches magazine-style prose; avoids the generic chat-UI
                // default dot.
                return indent + "\u{2014}\u{2002}" + line[match.upperBound...]
            }

            if line.trimmingCharacters(in: .whitespaces).range(
                of: #"^([-*_])\1{2,}$"#,
                options: .regularExpression
            ) != nil {
                return ""
            }

            return line
        }

        lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }

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
        let pattern = #"^(\s*(?:\u{2014}\u{2002})?)\*\*([^*\n\[\]]{2,30})\*\*\s+([a-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        let range = NSRange(line.startIndex..., in: line)
        return regex.stringByReplacingMatches(
            in: line,
            range: range,
            withTemplate: "$1**$2**\u{2002}$3"
        )
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
