#!/usr/bin/env swift

// check-help-doc-budget.swift
//
// Build Phase 3 of the grounding-doc pipeline (spec v5 §11, §17 gotcha 2–3).
//
// Loads the concatenated `Resources/help-content.md` and verifies it fits
// under the 1500-token ceiling. Uses `SystemLanguageModel.default.tokenCount(for:)`
// — Apple's on-device tokenizer — which is the only reliable measurement
// (no public tokenizer ships with the SDK).
//
// Exits non-zero on over-budget. Prints the actual count on success.
//
// Fallback path: on build hosts without Apple Intelligence eligibility
// (e.g. CI runners on non-AI Macs, or a dev on a pre-26 OS), we use a
// conservative 4-chars-per-token heuristic. This is ~20 % pessimistic on
// English prose, which is acceptable for a build-time guardrail: we'd
// rather reject a doc that's borderline than ship an over-budget binary.

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

let repoRoot: URL = {
    if let srcroot = ProcessInfo.processInfo.environment["SRCROOT"] {
        return URL(fileURLWithPath: srcroot)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

let docFile = repoRoot
    .appendingPathComponent("Resources")
    .appendingPathComponent("help-content.md")

guard let content = try? String(contentsOf: docFile, encoding: .utf8) else {
    FileHandle.standardError.write("check-help-doc-budget: cannot read \(docFile.path) — did concat-help-content run?\n".data(using: .utf8)!)
    exit(1)
}

let budget = 1500

func charHeuristicTokens(_ s: String) -> Int {
    // 4-chars-per-token is the widely-cited English-prose approximation.
    // We conservatively use 3.5 to err on the high side.
    Int(ceil(Double(s.count) / 3.5))
}

#if canImport(FoundationModels)
if #available(macOS 26.4, *) {
    if SystemLanguageModel.default.availability == .available {
        // `tokenCount(for:)` is async throws as of macOS 26.4.
        let semaphore = DispatchSemaphore(value: 0)
        var measured: Int?
        var measureError: Error?
        Task {
            do {
                measured = try await SystemLanguageModel.default.tokenCount(for: content)
            } catch {
                measureError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let err = measureError {
            FileHandle.standardError.write("check-help-doc-budget: tokenCount threw \(err) — falling back to heuristic.\n".data(using: .utf8)!)
        } else if let count = measured {
            if count > budget {
                FileHandle.standardError.write(
                    "check-help-doc-budget: FAIL — help-content.md is \(count) tokens (budget: \(budget)). Trim the base prose or compress fragments.\n".data(using: .utf8)!
                )
                exit(1)
            }
            print("check-help-doc-budget: OK — \(count) tokens (budget: \(budget), measured via SystemLanguageModel)")
            exit(0)
        }
    } else {
        // Apple Intelligence installed but not available (region, OS
        // staging, user-disabled). Fall through to heuristic path below.
        FileHandle.standardError.write("check-help-doc-budget: SystemLanguageModel unavailable — falling back to char heuristic.\n".data(using: .utf8)!)
    }
}
#endif

// Fallback: conservative char-based estimate.
let est = charHeuristicTokens(content)
if est > budget {
    FileHandle.standardError.write(
        "check-help-doc-budget: FAIL (heuristic) — help-content.md is ~\(est) tokens estimated (budget: \(budget)). Install macOS 26+ with Apple Intelligence for precise measurement.\n".data(using: .utf8)!
    )
    exit(1)
}
print("check-help-doc-budget: OK (heuristic) — ~\(est) tokens estimated (budget: \(budget), install macOS 26+ for exact count)")
