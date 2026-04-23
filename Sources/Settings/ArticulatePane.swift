import KeyboardShortcuts
import SwiftUI

/// Settings pane for AI features — covers both Articulate (voice-driven
/// and fixed-prompt selection rewrites) and the Transform / Auto-correct
/// provider configuration, since all share `LLMConfiguration`. The
/// user-visible display name is "AI" (design doc §4 / §7).
///
/// v1.5 rename: `RewritePane` → `ArticulatePane`. File renamed accordingly.
struct ArticulatePane: View {
    @ObservedObject private var config = LLMConfiguration.shared
    @AppStorage("jot.askjot.allowCloud") private var allowCloudAskJot = false
    @Environment(\.helpNavigator) private var navigator
    @State private var apiKeyInput: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var isTesting = false

    private enum TestStatus: Equatable {
        case idle
        case success
        case failure(String)
    }

    private var isAppleIntelligenceSelected: Bool {
        config.provider == .appleIntelligence
    }

    private var isAppleIntelligenceAvailable: Bool {
        AppleIntelligenceClient.isAvailable
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section("Provider") {
                    HStack {
                        Picker("Provider", selection: $config.provider) {
                            ForEach(LLMProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        InfoPopoverButton(
                            title: "Provider",
                            body: "Which service handles Auto-correct and Articulate. Apple Intelligence runs on-device (free, no API key). OpenAI, Anthropic, Gemini, and local Ollama round out the options.",
                            helpAnchor: "ai-cloud-providers"
                        )
                    }
                    .id("ai-provider")
                    if !isAppleIntelligenceSelected {
                        Toggle("Allow Ask Jot to use this provider", isOn: $allowCloudAskJot)
                        Text("Sends your Ask Jot conversation and Jot's help content to the selected provider using your API key.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if isAppleIntelligenceSelected {
                        if isAppleIntelligenceAvailable {
                            HStack(spacing: 6) {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(.secondary)
                                Text("On-device via Apple Foundation Models. No API key required.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        } else {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Apple Intelligence isn't available on this Mac. Requires macOS 26.0 or later on Apple Silicon with Apple Intelligence enabled.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    } else {
                        HStack {
                            TextField("Base URL (leave empty for default)", text: config.baseURLBinding(for: config.provider))
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                            InfoPopoverButton(
                                title: "Base URL",
                                body: "Optional override for the provider's API endpoint. Leave empty to use the provider default. Handy for OpenAI-compatible proxies or self-hosted endpoints.",
                                helpAnchor: "ai-custom-base-url"
                            )
                        }
                        Text("Default: \(config.provider.defaultBaseURL)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack {
                            TextField("Model (leave empty for default)", text: config.modelBinding(for: config.provider))
                                .textFieldStyle(.roundedBorder)
                            InfoPopoverButton(
                                title: "Model",
                                body: "Which model the provider should route requests to. Leave empty to use the provider default. Use this to opt into newer or cheaper variants your account supports.",
                                helpAnchor: "ai-cloud-providers"
                            )
                        }
                        Text("Default: \(config.provider.defaultModel)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if config.provider != .ollama && config.provider != .appleIntelligence {
                    Section("Authentication") {
                        HStack {
                            SecureField("API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .onAppear { apiKeyInput = config.apiKey(for: config.provider) }
                                .onChange(of: config.provider) { _, newProvider in
                                    apiKeyInput = config.apiKey(for: newProvider)
                                }
                                .onChange(of: apiKeyInput) { _, newValue in
                                    config.setAPIKey(newValue, for: config.provider)
                                }
                            InfoPopoverButton(
                                title: "API Key",
                                body: "Stored in your macOS Keychain, never written to disk in plaintext. When set: Jot authenticates requests to the selected provider. Leave empty when using Ollama locally or Apple Intelligence on-device.",
                                helpAnchor: "ai-custom-base-url"
                            )
                        }
                    }
                }

                Section("Articulate") {
                    HStack {
                        Text("Articulate (Custom)")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .articulateCustom)
                    }
                    .id("articulate-custom")
                    Text("Select text, press the shortcut, speak your instruction.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    HStack {
                        Text("Articulate")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .articulate)
                    }
                    .id("articulate-fixed")
                    Text("Select text and press the shortcut — Jot articulates it with a built-in prompt. No voice step.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Section("Prompt") {
                    CustomizePromptDisclosure(
                        label: "Shared system prompt",
                        text: $config.articulatePrompt,
                        defaultValue: ArticulatePrompt.default,
                        info: .init(
                            title: "Shared system prompt",
                            body: "The foundation of every Articulate call. When you trigger Articulate (fixed or custom), Jot sends this text plus a short branch-specific tendency it picks automatically based on your instruction — voice-preserving, shape change, translation, or code. Cleanup has its own separate prompt for transcripts; editing this here does not affect Cleanup. Edit with care — malformed prompts can break Articulate.",
                            helpAnchor: "ai-editable-prompts"
                        )
                    )
                }

                Section("Test") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button {
                                Task { await testConnection() }
                            } label: {
                                if isTesting {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Testing…")
                                    }
                                } else {
                                    Text("Test Connection")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.accentColor)

                            Spacer()
                            InfoPopoverButton(
                                title: "Test Connection",
                                body: "Runs a minimal check against your provider to confirm availability. When it succeeds: Auto-correct becomes enableable. Re-test after changing provider, URL, or key.",
                                helpAnchor: "ai-test-connection"
                            )
                        }

                        switch testStatus {
                        case .idle:
                            EmptyView()
                        case .success:
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Connection verified")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        case .failure(let message):
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { consumePendingSettingsFieldAnchor(with: proxy) }
            .onChange(of: navigator.pendingSettingsFieldAnchor) { _, _ in
                consumePendingSettingsFieldAnchor(with: proxy)
            }
        }
        .navigationTitle("AI")
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        if config.provider == .appleIntelligence {
            // Short-circuit: Apple Intelligence success is purely about
            // local availability; no request to make.
            if AppleIntelligenceClient.isAvailable {
                testStatus = .success
            } else {
                testStatus = .failure("Apple Intelligence isn't available on this Mac.")
            }
            return
        }
        let success = await LLMClient().healthCheck()
        if success {
            testStatus = .success
        } else {
            testStatus = .failure("Connection failed")
        }
    }

    private func consumePendingSettingsFieldAnchor(with proxy: ScrollViewProxy) {
        guard let anchor = navigator.pendingSettingsFieldAnchor,
              Self.supportedSettingsAnchors.contains(anchor)
        else { return }
        withAnimation {
            proxy.scrollTo(anchor, anchor: .top)
        }
        navigator.clearPendingSettingsFieldAnchor()
    }

    private static let supportedSettingsAnchors: Set<String> = [
        "ai-provider",
        "articulate-custom",
        "articulate-fixed",
    ]
}
