#!/usr/bin/env swift

// concat-help-content.swift
//
// Build Phase 2 of the grounding-doc pipeline (spec v5 §11).
//
// Reads `Resources/help-content-base.md`, replaces every
// `<!-- FRAGMENT: name -->` placeholder with the contents of
// `Resources/fragments/name.md`, and writes the concatenated result to
// `Resources/help-content.md`.
//
// Fails with a clear error on:
//   * missing base file,
//   * an unmatched placeholder (fragment file not present),
//   * an unused fragment (sanity check — a fragment with no placeholder
//     is almost always a typo; logged as a warning, not a failure).

import Foundation

let repoRoot: URL = {
    if let srcroot = ProcessInfo.processInfo.environment["SRCROOT"] {
        return URL(fileURLWithPath: srcroot)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

// Flavor builds (e.g. flavor_1) can override the base file and extend the
// fragment search path via two env vars. When both are set the flavor
// base file is used instead of the shared one, and the flavor fragments
// directory is appended to the fragment search path. When neither is set
// — the public/Sony case — behavior is byte-identical to before this
// change. Setting only one without the other is treated as unset so a
// half-configured environment can't silently change the output.
let flavorBaseOverride = ProcessInfo.processInfo.environment["JOT_FLAVOR_BASE"]
let flavorFragmentsOverride = ProcessInfo.processInfo.environment["JOT_FLAVOR_FRAGMENTS_DIR"]
let flavorActive =
    (flavorBaseOverride?.isEmpty == false) && (flavorFragmentsOverride?.isEmpty == false)

let baseFile: URL = {
    if flavorActive, let raw = flavorBaseOverride {
        let url = URL(fileURLWithPath: raw)
        return url.path.hasPrefix("/") ? url : repoRoot.appendingPathComponent(raw)
    }
    return repoRoot
        .appendingPathComponent("Resources")
        .appendingPathComponent("help-content-base.md")
}()

let fragmentsDir = repoRoot
    .appendingPathComponent("Resources")
    .appendingPathComponent("fragments")

let flavorFragmentsDir: URL? = {
    guard flavorActive, let raw = flavorFragmentsOverride else { return nil }
    let url = URL(fileURLWithPath: raw)
    return url.path.hasPrefix("/") ? url : repoRoot.appendingPathComponent(raw)
}()

// Fragment search path: shared dir first (so shared fragments keep
// resolving), then flavor dir when active (so flavor-only fragments
// resolve without needing a matching entry under Resources/).
let fragmentSearchDirs: [URL] = {
    var dirs: [URL] = [fragmentsDir]
    if let extra = flavorFragmentsDir {
        dirs.append(extra)
    }
    return dirs
}()

let outFile = repoRoot
    .appendingPathComponent("Resources")
    .appendingPathComponent("help-content.md")

guard let base = try? String(contentsOf: baseFile, encoding: .utf8) else {
    FileHandle.standardError.write("concat-help-content: cannot read \(baseFile.path)\n".data(using: .utf8)!)
    exit(1)
}

// Extract `<!-- FRAGMENT: name -->` placeholders.
let pattern = #"<!--\s*FRAGMENT:\s*([a-zA-Z0-9_-]+)\s*-->"#
guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
    FileHandle.standardError.write("concat-help-content: regex compile failed\n".data(using: .utf8)!)
    exit(1)
}

let ns = base as NSString
let matches = regex.matches(in: base, range: NSRange(location: 0, length: ns.length))

var referenced = Set<String>()
for m in matches where m.numberOfRanges > 1 {
    referenced.insert(ns.substring(with: m.range(at: 1)))
}

// Resolve a fragment name to a file URL by trying each search dir in
// order. Returns nil when no search dir has the fragment.
func resolveFragment(_ name: String) -> URL? {
    for dir in fragmentSearchDirs {
        let candidate = dir.appendingPathComponent("\(name).md")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
    }
    return nil
}

// Verify each referenced fragment exists in at least one search dir.
for name in referenced.sorted() {
    if resolveFragment(name) == nil {
        let searched = fragmentSearchDirs.map { $0.path }.joined(separator: ", ")
        FileHandle.standardError.write(
            "concat-help-content: ERROR — placeholder <!-- FRAGMENT: \(name) --> has no matching \(name).md in: \(searched)\n".data(using: .utf8)!
        )
        exit(1)
    }
}

// Warn on unused fragments across every search dir.
var emittedOnDisk = Set<String>()
for dir in fragmentSearchDirs {
    if let onDisk = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
        for name in onDisk where name.hasSuffix(".md") {
            emittedOnDisk.insert(String(name.dropLast(3)))
        }
    }
}
for orphan in emittedOnDisk.subtracting(referenced).sorted() {
    FileHandle.standardError.write(
        "concat-help-content: warning — fragment '\(orphan)' has no placeholder in the base file\n".data(using: .utf8)!
    )
}

// Perform the substitution. Go back-to-front so earlier ranges stay valid.
var out = base
let reversedMatches = matches.reversed()
for m in reversedMatches where m.numberOfRanges > 1 {
    let name = ns.substring(with: m.range(at: 1))
    guard let fragURL = resolveFragment(name) else {
        FileHandle.standardError.write("concat-help-content: cannot resolve fragment '\(name)'\n".data(using: .utf8)!)
        exit(1)
    }
    guard let raw = try? String(contentsOf: fragURL, encoding: .utf8) else {
        FileHandle.standardError.write("concat-help-content: cannot read \(fragURL.path)\n".data(using: .utf8)!)
        exit(1)
    }
    // Trim trailing newlines — inline splices shouldn't double-line-break.
    let fragment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let nsOut = out as NSString
    let fullRange = m.range(at: 0)
    out = nsOut.replacingCharacters(in: fullRange, with: fragment)
}

try? out.write(to: outFile, atomically: true, encoding: .utf8)
print("concat-help-content: wrote \(outFile.path) (\(out.count) chars, \(referenced.count) placeholders filled)")
