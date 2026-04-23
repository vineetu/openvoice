import AppKit
import SwiftUI

/// Editorial design tokens for the Ask Jot surface. Ask Jot has its own
/// voice — warm paper, oxblood accent, New York serif prose — that
/// deliberately departs from the rest of Jot's standard macOS treatment.
/// The rest of the app uses system accent colors and SF; Ask Jot reads as
/// a magazine column, not a chat bubble.
enum AskJotPalette {
    /// Warm off-white "paper" background — ~2% toward cream. Dark mode
    /// flips to a near-black with a whisper of warmth.
    static let paper = NSColor(name: "askJotPaper", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0x17 / 255.0, green: 0x17 / 255.0, blue: 0x1A / 255.0, alpha: 1)
        } else {
            return NSColor(red: 0xFB / 255.0, green: 0xFA / 255.0, blue: 0xF6 / 255.0, alpha: 1)
        }
    })

    /// Primary body text — near-black on paper, near-white on dark.
    static let ink = NSColor(name: "askJotInk", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0xED / 255.0, green: 0xED / 255.0, blue: 0xEE / 255.0, alpha: 1)
        } else {
            return NSColor(red: 0x1D / 255.0, green: 0x1D / 255.0, blue: 0x1F / 255.0, alpha: 1)
        }
    })

    /// Muted text — captions, bylines, secondary metadata.
    static let inkMuted = NSColor(name: "askJotInkMuted", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0x8C / 255.0, green: 0x8C / 255.0, blue: 0x92 / 255.0, alpha: 1)
        } else {
            return NSColor(red: 0x6B / 255.0, green: 0x6B / 255.0, blue: 0x70 / 255.0, alpha: 1)
        }
    })

    /// Accent — links, pull-quote rule, streaming pulse. Explicitly
    /// Apple's system blue (#007AFF / #0A84FF dark) rather than
    /// `controlAccentColor` so it stays blue even if the user's macOS
    /// system accent is set to orange/pink/etc. Blue is Jot's visual
    /// identity across the app.
    static let inkAccent = NSColor.systemBlue

    /// Hairline rules, dividers. Ink at low alpha; adapts to dark.
    static let rule = NSColor(name: "askJotRule", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0xED / 255.0, green: 0xED / 255.0, blue: 0xEE / 255.0, alpha: 0.14)
        } else {
            return NSColor(red: 0x1D / 255.0, green: 0x1D / 255.0, blue: 0x1F / 255.0, alpha: 0.10)
        }
    })

    /// User message left-rule — slightly heavier than the plain hairline
    /// so the margin note carries semantic weight.
    static let userMark = NSColor(name: "askJotUserMark", dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0xED / 255.0, green: 0xED / 255.0, blue: 0xEE / 255.0, alpha: 0.55)
        } else {
            return NSColor(red: 0x1D / 255.0, green: 0x1D / 255.0, blue: 0x1F / 255.0, alpha: 0.40)
        }
    })

    // MARK: SwiftUI bridge

    static var paperColor: Color { Color(nsColor: paper) }
    static var inkColor: Color { Color(nsColor: ink) }
    static var inkMutedColor: Color { Color(nsColor: inkMuted) }
    static var inkAccentColor: Color { Color(nsColor: inkAccent) }
    static var ruleColor: Color { Color(nsColor: rule) }
    static var userMarkColor: Color { Color(nsColor: userMark) }
}

/// Editorial typography scale. Everything Ask Jot renders lives here.
/// Body prose is New York serif; UI chrome stays in SF Pro.
enum AskJotType {
    // Assistant prose — New York serif.
    static let body = NSFont.newYork(size: 15, weight: .regular)
    static let bodySemibold = NSFont.newYork(size: 15, weight: .semibold)
    static let bodyItalic = NSFont.newYork(size: 15, weight: .regular, italic: true)

    // Monospace (inline code).
    static let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)

    // Masthead & headings (serif).
    static let masthead = NSFont.newYork(size: 22, weight: .regular)
    static let heading = NSFont.newYork(size: 16, weight: .semibold)
    static let emptyHeadline = NSFont.newYork(size: 24, weight: .regular)

    // Byline — small caps in serif.
    static let byline = Font.system(size: 10, weight: .medium, design: .serif)
    static let bylineTracking: CGFloat = 1.6

    // UI chrome — SF Pro.
    static let userBody = Font.system(size: 14, weight: .regular, design: .default)
    static let caption = Font.system(size: 10, weight: .regular, design: .default)
    static let subtitleItalic = Font.system(size: 11, weight: .regular, design: .serif).italic()
}

extension NSFont {
    /// Build a New York serif NSFont at a given size/weight. Falls back
    /// to the system serif face if "New York" isn't resolvable (shouldn't
    /// happen on macOS 14+ but defensive).
    static func newYork(size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        var descriptor = base.withDesign(.serif) ?? base
        if italic {
            descriptor = descriptor.withSymbolicTraits(.italic)
        }
        return NSFont(descriptor: descriptor, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    }
}
