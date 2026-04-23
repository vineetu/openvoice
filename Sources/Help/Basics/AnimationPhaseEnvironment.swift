import SwiftUI

// MARK: - Animation phase (shared timeline)

/// Phase of the shared Basics-tab illustration timeline, ∈ [0, 1).
///
/// `HelpBasicsView` hosts a single `TimelineView(.animation(minimumInterval:))`
/// that computes this value over a 6-second loop and injects it via
/// `.environment(\.animationPhase, phase)`. Each `HeroIllustration` reads the
/// phase out of the environment to drive its keyframes.
///
/// Centralizing phase here means:
/// - all three hero illustrations move in lockstep (no drift between them),
/// - Reduce Motion / search-pause logic lives in one place (HelpBasicsView
///   computes an `effectivePhase` and injects *that*),
/// - phase1b (Advanced) and phase1c (HelpPane/search) can read the same
///   environment key if they need to freeze motion elsewhere.
///
/// Default value is `0.6`, matching the Reduce Motion "resolved" keyframe —
/// so a HeroIllustration rendered outside a TimelineView (previews, tests)
/// still produces a sensible, non-empty image.
private struct AnimationPhaseKey: EnvironmentKey {
    static let defaultValue: Double = 0.6
}

extension EnvironmentValues {
    /// The shared Basics-tab animation phase, ∈ [0, 1).
    ///
    /// Set by HelpBasicsView inside a TimelineView. Reduce Motion locks it
    /// to 0.6. Active search freezes it at the value captured when search
    /// began. HeroIllustration reads it to drive keyframes.
    var animationPhase: Double {
        get { self[AnimationPhaseKey.self] }
        set { self[AnimationPhaseKey.self] = newValue }
    }
}
