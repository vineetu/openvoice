#!/usr/bin/env swift

// Count tokens for every variant under docs/research/variants/.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

setlinebuf(stdout)

#if canImport(FoundationModels)
guard #available(macOS 26.4, *) else { print("need 26.4"); exit(1) }
guard SystemLanguageModel.default.availability == .available else {
    print("Apple Intelligence unavailable"); exit(1)
}

@available(macOS 26.4, *)
func run() async {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("docs/research/variants")
    let names = ["doc-control.md", "doc-whitespace.md", "doc-keyvalue.md",
                 "doc-telegraphic.md", "doc-structured.md",
                 "doc-E-telegraphic-shorthand.md", "doc-F-symbolic.md",
                 "doc-G-dsv.md", "doc-H-aliasing.md", "doc-I-md-compact.md",
                 "doc-J-hybrid.md",
                 "instr-v5-current.txt", "instr-example-first.txt",
                 "instr-strong-imperatives.txt", "instr-minimalist.txt",
                 "instr-refusal-contract.txt", "instr-hybrid.txt"]
    for n in names {
        let url = root.appendingPathComponent(n)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            print("\(n): MISSING"); continue
        }
        let t = (try? await SystemLanguageModel.default.tokenCount(for: s)) ?? -1
        print(String(format: "%-32s  %5d tokens  %5d chars", (n as NSString).utf8String!, t, s.count))
    }
}

if #available(macOS 26.4, *) {
    let sem = DispatchSemaphore(value: 0)
    Task { await run(); sem.signal() }
    sem.wait()
}
#endif
