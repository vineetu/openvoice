// Sources/AskJot/Cloud/CloudChatStream.swift — canonical shared protocol for cloud chat streaming. Per-provider files conform. Unification point from docs/plans/llm-unification-deferred.md; see that doc for the long-term AIService merge.

import Foundation

protocol CloudChatStream {
    func streamChat(
        messages: [CloudChatMessage],
        systemInstructions: String,
        showFeatureTool: @escaping (String) async -> String,
        apiKey: String,
        baseURL: String,
        model: String,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error>
}

struct CloudChatMessage: Equatable, Sendable {
    let role: CloudChatRole
    let content: String
}

enum CloudChatRole: Equatable, Sendable {
    case user
    case assistant
    case tool(callId: String, name: String)
}
