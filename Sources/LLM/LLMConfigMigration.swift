import Foundation

/// One-shot migration from the v1.5.0 flat `{jot.llm.baseURL, jot.llm.model,
/// jot.llm.apiKey}` schema to the v1.5.1 per-provider buckets. Runs exactly
/// once per machine (guarded by `jot.migration.perProviderV1`).
///
/// Does NOT clobber per-provider values the user has already entered in the
/// new build — only fills in EMPTY per-provider buckets from the old flat
/// values. Old flat keys are LEFT IN PLACE as a safety net; a future cleanup
/// release can drop them.
enum LLMConfigMigration {
    private static let flagKey = "jot.migration.perProviderV1"
    private static let trimFlagKey = "jot.migration.trimURLsV1"

    static func runIfNeeded() {
        trimStoredValuesIfNeeded()
        runPerProviderBucketsIfNeeded()
    }

    /// Strip leading/trailing whitespace + newlines from any already-stored
    /// per-provider baseURLs/models and keychain API keys. Users who pasted
    /// URLs with trailing linebreaks (common Chrome paste artifact) end up
    /// with `https://.../v1\n` which `URL(string:)` happily accepts but the
    /// `\n` gets percent-encoded to `%0A` on the request path. Runs once.
    private static func trimStoredValuesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: trimFlagKey) else { return }
        defer { defaults.set(true, forKey: trimFlagKey) }

        for provider in [LLMProvider.openai, .anthropic, .gemini, .ollama] {
            for suffix in ["baseURL", "model"] {
                let key = "jot.llm.\(provider.rawValue).\(suffix)"
                if let raw = defaults.string(forKey: key) {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed != raw {
                        if trimmed.isEmpty {
                            defaults.removeObject(forKey: key)
                        } else {
                            defaults.set(trimmed, forKey: key)
                        }
                    }
                }
            }
            let apiKey = "jot.llm.\(provider.rawValue).apiKey"
            if let data = KeychainHelper.load(key: apiKey),
               let raw = String(data: data, encoding: .utf8) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed != raw {
                    if trimmed.isEmpty {
                        KeychainHelper.delete(key: apiKey)
                    } else {
                        KeychainHelper.save(key: apiKey, data: Data(trimmed.utf8))
                    }
                }
            }
        }
    }

    private static func runPerProviderBucketsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flagKey) else { return }
        defer { defaults.set(true, forKey: flagKey) }

        let providerRaw = defaults.string(forKey: "jot.llm.provider") ?? ""
        guard let provider = LLMProvider(rawValue: providerRaw) else { return }

        let oldBaseURL = defaults.string(forKey: "jot.llm.baseURL") ?? ""
        let oldModel = defaults.string(forKey: "jot.llm.model") ?? ""
        let oldAPIKey: String = {
            guard let data = KeychainHelper.load(key: "jot.llm.apiKey") else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }()

        let baseURLKey = "jot.llm.\(provider.rawValue).baseURL"
        let modelKey = "jot.llm.\(provider.rawValue).model"
        let apiKeychainKey = "jot.llm.\(provider.rawValue).apiKey"

        let currentBucketBaseURL = defaults.string(forKey: baseURLKey) ?? ""
        let currentBucketModel = defaults.string(forKey: modelKey) ?? ""
        let currentBucketAPIKey: String = {
            guard let data = KeychainHelper.load(key: apiKeychainKey) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }()

        if currentBucketBaseURL.isEmpty && !oldBaseURL.isEmpty {
            defaults.set(oldBaseURL, forKey: baseURLKey)
        }
        if currentBucketModel.isEmpty && !oldModel.isEmpty {
            defaults.set(oldModel, forKey: modelKey)
        }
        if currentBucketAPIKey.isEmpty && !oldAPIKey.isEmpty {
            KeychainHelper.save(key: apiKeychainKey, data: Data(oldAPIKey.utf8))
        }
    }
}
