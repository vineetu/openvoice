import Foundation

public enum LogRedactor {
    public static func redact(_ text: String, using results: [PrivacyCheckResult]) -> (text: String, summary: String) {
        // Coalesce overlapping findings before applying replacements.
        // Without this, two corpus strings whose matches overlap in the
        // same log line (e.g. a Rewrite `selectionText` that's a
        // substring of the same row's `output`) would have their
        // original ranges applied sequentially against a mutating
        // string — `String.replaceSubrange` would trip an out-of-bounds
        // trap once the first replacement shifted the indices.
        let coalesced = coalesce(results.flatMap(\.findings))
        let findings = coalesced.sorted { $0.range.lowerBound > $1.range.lowerBound }
        var output = text

        for finding in findings {
            let label: String
            switch finding.kind {
            case .apiKeys:
                label = "[REDACTED API KEY]"
            case .customEndpoint:
                label = "[REDACTED CUSTOM ENDPOINT]"
            case .transcripts:
                label = "[REDACTED TRANSCRIPT]"
            case .homeFolder:
                label = "/Users/<redacted>/"
            case .credentialURLs:
                label = "[REDACTED URL CREDENTIAL]"
            }
            output.replaceSubrange(finding.range, with: label)
        }

        let counts = Dictionary(grouping: findings, by: \.kind).mapValues(\.count)
        let summaryParts = PrivacyCheckKind.allCases.compactMap { kind -> String? in
            guard let count = counts[kind], count > 0 else { return nil }
            return "\(count) \(kind.rawValue)"
        }

        let header = """
        # Jot log - redacted by scanner v1
        # Categories removed: \(summaryParts.isEmpty ? "none" : summaryParts.joined(separator: ", "))
        # ---

        """

        return (header + output, summaryParts.joined(separator: ", "))
    }

    /// Merge overlapping findings into the *union* of their ranges so a
    /// later match's tail can't leak past a kept earlier match. Sort
    /// ascending by `lowerBound`; for each new finding, either fold it
    /// into the previous kept finding (extending the range to the max
    /// `upperBound`) or append it as a new region. Conflict-free by
    /// construction since the resulting ranges never overlap.
    ///
    /// The merged finding inherits the *earlier* finding's `kind` —
    /// callers that care about the precise kind should split the corpus
    /// before calling. For the rewrite-corpus case (selectionText /
    /// instructionText / output all redact to `[REDACTED TRANSCRIPT]`)
    /// this doesn't change the rendered label.
    private static func coalesce(_ findings: [PrivacyFinding]) -> [PrivacyFinding] {
        let sorted = findings.sorted { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            return lhs.range.upperBound > rhs.range.upperBound
        }
        var kept: [PrivacyFinding] = []
        for finding in sorted {
            if var prev = kept.last, finding.range.lowerBound < prev.range.upperBound {
                if finding.range.upperBound > prev.range.upperBound {
                    prev = PrivacyFinding(
                        kind: prev.kind,
                        snippet: prev.snippet,
                        range: prev.range.lowerBound..<finding.range.upperBound
                    )
                    kept[kept.count - 1] = prev
                }
                continue
            }
            kept.append(finding)
        }
        return kept
    }
}
