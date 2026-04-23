import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// FoundationModels `Tool` the chatbot uses to deep-link into the Help
/// tab. Spec §7.
///
/// The model is instructed to cite slugs inline in square brackets; the
/// store's post-processing pass extracts those slugs from the final
/// assistant text and invokes this tool once per unique deep-linkable
/// slug (capped at 2 per turn). Rationale: small models are flaky at
/// inline tool invocation — driving the tool from text is more reliable
/// and doesn't burn tokens on the tool schema appearing in thinking.
///
/// Guards:
///   * Unknown slug → `"Feature not available"` (no navigation).
///   * Non-deep-linkable slug (the 2 plain Cleanup sub-rows) →
///     `"Feature not available"` — the post-processing filter should
///     have rejected them earlier; this is a belt-and-suspenders guard.
///
/// On a valid call, returns `"Shown"` but deliberately does not stage
/// navigation. The chat UI rewrites `[slug]` into inline links, and the
/// click handler is the sole writer for `switchTab`, `pendingExpansion`,
/// `highlightedFeatureId`, and `sidebarSelection`.
@available(macOS 26.0, *)
struct ShowFeatureTool: Tool {
    let navigator: HelpNavigator

    let name = "showFeature"
    let description = """
    Highlight a specific feature card in the Jot Help page. Call this when \
    you mention a feature by its slug so the user can see the relevant \
    surface.
    """

    @Generable
    struct Arguments {
        @Guide(description: "The feature slug from the documentation, in square brackets")
        let featureId: String
    }

    /// Returns a plain `String` (which conforms to
    /// `PromptRepresentable`, the `Tool.Output` requirement in the
    /// 26.4 FoundationModels interface). The string is fed back into
    /// the model turn; we keep it short so it doesn't bloat the
    /// assistant's context.
    func call(arguments: Arguments) async throws -> String {
        guard let feature = Feature.bySlug(arguments.featureId),
              feature.isDeepLinkable
        else {
            return "Feature not available"
        }

        _ = navigator
        _ = feature
        // Keep Ask Jot visible; the chat pane must not navigate away from itself during a response.
        // Pre-staging was removed too: the slug-link click handler recomputes the Help target in O(1).
        return "Shown"
    }
}
#endif
