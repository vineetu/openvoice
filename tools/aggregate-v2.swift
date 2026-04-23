#!/usr/bin/env swift

// aggregate-v2.swift — read docs/research/v2-out/*.json and print a summary
// table: label | n_runs | judge_pass% | slug_cited% | sharp_fix_clean%
// | refusal_marker% | errored% | median_totalMs

import Foundation

struct PerRun: Codable {
    let label: String
    let questionId: Int
    let run: Int
    let promptSent: String
    let condensed: Bool
    let condenseMs: Double
    let firstTokenMs: Double
    let totalMs: Double
    let answerText: String
    let answerTokens: Int
    let slugCited: Bool
    let sharpFixClean: Bool
    let refusalMarker: Bool
    let mustOk: Bool
    let mustNotOk: Bool
    let judgePass: Bool
    let judgeVerdicts: [String]
    let errored: Bool
    let errorMessage: String?
}

let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("docs/research/v2-out")
let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
let jsons = files.filter { $0.hasSuffix(".json") }.sorted()

let expectRefusalIds: Set<Int> = [12, 13, 14, 15]
let offtopicIds: Set<Int> = [13, 14, 15]
let sharpFixIds: Set<Int> = [3, 4]
// Q102 / Q103 / Q105 / Q110 are verbose. Q101 = verbose Q1, etc.
let slugExpectedIds: Set<Int> = [1, 2, 3, 4, 5, 7, 8, 10, 101, 102, 103, 105, 110]

func median(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted(); return s[s.count/2]
}
func pct(_ bs: [Bool]) -> Double {
    bs.isEmpty ? 0 : Double(bs.filter { $0 }.count) / Double(bs.count) * 100
}

print("file\tn\tjudge%\tslug%\tsharp%\trefusal%\terr%\tmedLat\tcondCount")
for f in jsons {
    let url = dir.appendingPathComponent(f)
    guard let data = try? Data(contentsOf: url),
          let runs = try? JSONDecoder().decode([PerRun].self, from: data)
    else { continue }
    let n = runs.count
    let judgeOnes = runs.filter { !$0.errored }.map(\.judgePass)
    let slugEligible = runs.filter { slugExpectedIds.contains($0.questionId) }
    let slugs = slugEligible.map(\.slugCited)
    let sharp = runs.filter { sharpFixIds.contains($0.questionId) }.map(\.sharpFixClean)
    let refu = runs.filter { expectRefusalIds.contains($0.questionId) }.map(\.refusalMarker)
    let err = runs.map(\.errored)
    let lat = runs.map(\.totalMs).filter { $0 > 0 }
    let condCount = runs.filter { $0.condensed }.count
    print(String(format: "%-28s\t%d\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t%d",
                 (f as NSString).utf8String!,
                 n, pct(judgeOnes), pct(slugs), pct(sharp), pct(refu), pct(err),
                 median(lat), condCount))
}

// Also print per-question deep-dive on errored runs
print("\n--- errored runs ---")
for f in jsons {
    let url = dir.appendingPathComponent(f)
    guard let data = try? Data(contentsOf: url),
          let runs = try? JSONDecoder().decode([PerRun].self, from: data)
    else { continue }
    let errs = runs.filter { $0.errored }
    if errs.isEmpty { continue }
    print("\(f): \(errs.count) errored runs")
    for e in errs.prefix(3) {
        print("  q=\(e.questionId) run=\(e.run): \(e.errorMessage ?? "?")")
    }
}
