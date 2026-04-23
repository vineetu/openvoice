import Foundation

/// Resolved Help feature reference derived from an assistant-emitted slug.
/// Created at render time so the chat UI can substitute readable titles
/// while preserving the canonical slug for deep-link routing.
struct FeatureReference: Hashable, Identifiable {
    static let urlScheme = "jot-feature"

    let slug: String
    let title: String
    let tab: HelpTab
    let isDeepLinkable: Bool

    var id: String { slug }
    var url: URL? { URL(string: "\(Self.urlScheme)://\(slug)") }

    init?(slug: String) {
        guard let feature = Feature.bySlug(slug) else { return nil }
        self.slug = feature.slug
        self.title = feature.title
        self.tab = feature.tab
        self.isDeepLinkable = feature.isDeepLinkable
    }

    static func bySlug(_ slug: String) -> FeatureReference? {
        FeatureReference(slug: slug)
    }

    static func slug(from url: URL) -> String? {
        if let host = url.host(), !host.isEmpty {
            return host
        }

        let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmedPath.isEmpty ? nil : trimmedPath
    }
}
