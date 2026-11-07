import Foundation

// Wire types for the OpenAI Chat Completions API (also spoken by most OpenAI-compatible local
// servers such as Ollama and LM Studio). Only the fields we use are modelled.

public struct ChatMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case system, developer, user, assistant, tool }

    public var role: Role
    public var content: String?
    public var toolCalls: [ToolCall]?
    public var toolCallID: String?

    public init(role: Role, content: String?, toolCalls: [ToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    public static func system(_ text: String) -> ChatMessage { ChatMessage(role: .system, content: text) }
    public static func user(_ text: String) -> ChatMessage { ChatMessage(role: .user, content: text) }
    public static func assistant(_ text: String?, toolCalls: [ToolCall]? = nil) -> ChatMessage {
        ChatMessage(role: .assistant, content: text, toolCalls: (toolCalls?.isEmpty ?? true) ? nil : toolCalls)
    }
    public static func tool(_ callID: String, _ content: String) -> ChatMessage {
        ChatMessage(role: .tool, content: content, toolCallID: callID)
    }

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        // Assistant messages that only carry tool calls send `content: null`.
        if let content { try c.encode(content, forKey: .content) } else { try c.encodeNil(forKey: .content) }
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try c.encodeIfPresent(toolCallID, forKey: .toolCallID)
    }
}

public struct ToolCall: Codable, Hashable, Sendable {
    public struct Function: Codable, Hashable, Sendable {
        public var name: String
        public var arguments: String
        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }

    public var id: String
    public var type: String = "function"
    public var function: Function

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.function = Function(name: name, arguments: arguments)
    }
}

public struct ToolDefinition: Encodable, Sendable {
    public struct Function: Encodable, Sendable {
        public var name: String
        public var description: String
        public var parameters: JSONValue
    }

    public var type = "function"
    public var function: Function

    public init(name: String, description: String, parameters: JSONValue) {
        self.function = Function(name: name, description: description, parameters: parameters)
    }
}

public struct ChatRequest: Encodable, Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var tools: [ToolDefinition]?
    public var stream: Bool
    public var streamOptions: StreamOptions?
    public var maxCompletionTokens: Int?
    public var reasoningEffort: String?
    public var parallelToolCalls: Bool?
    public var user: String?

    public struct StreamOptions: Encodable, Sendable {
        public var includeUsage: Bool
        enum CodingKeys: String, CodingKey { case includeUsage = "include_usage" }
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream, user
        case streamOptions = "stream_options"
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
        case parallelToolCalls = "parallel_tool_calls"
    }
}

public struct TokenUsage: Codable, Hashable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var cachedTokens: Int?

    public init(promptTokens: Int = 0, completionTokens: Int = 0, cachedTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cachedTokens = cachedTokens
    }

    public var total: Int { promptTokens + completionTokens }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(promptTokens: a.promptTokens + b.promptTokens,
                   completionTokens: a.completionTokens + b.completionTokens,
                   cachedTokens: (a.cachedTokens ?? 0) + (b.cachedTokens ?? 0))
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case promptTokensDetails = "prompt_tokens_details"
    }

    struct PromptDetails: Codable { var cachedTokens: Int?; enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" } }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try c.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
        completionTokens = try c.decodeIfPresent(Int.self, forKey: .completionTokens) ?? 0
        cachedTokens = try c.decodeIfPresent(PromptDetails.self, forKey: .promptTokensDetails)?.cachedTokens
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(promptTokens, forKey: .promptTokens)
        try c.encode(completionTokens, forKey: .completionTokens)
        try c.encodeIfPresent(cachedTokens.map { PromptDetails(cachedTokens: $0) }, forKey: .promptTokensDetails)
    }
}

/// One `data:` payload of a streamed response.
public struct ChatStreamChunk: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public struct Delta: Decodable, Sendable {
            public var content: String?
            public var toolCalls: [ToolCallDelta]?
            enum CodingKeys: String, CodingKey { case content; case toolCalls = "tool_calls" }
        }
        public var index: Int?
        public var delta: Delta?
        public var finishReason: String?
        enum CodingKeys: String, CodingKey { case index, delta; case finishReason = "finish_reason" }
    }

    public struct ToolCallDelta: Decodable, Sendable {
        public struct FunctionDelta: Decodable, Sendable {
            public var name: String?
            public var arguments: String?
        }
        public var index: Int?
        public var id: String?
        public var function: FunctionDelta?
    }

    public var choices: [Choice]?
    public var usage: TokenUsage?
}

/// Non-streamed response (used as a fallback and by tests).
public struct ChatCompletion: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public struct Message: Decodable, Sendable {
            public var content: String?
            public var toolCalls: [ToolCall]?
            enum CodingKeys: String, CodingKey { case content; case toolCalls = "tool_calls" }
        }
        public var message: Message
        public var finishReason: String?
        enum CodingKeys: String, CodingKey { case message; case finishReason = "finish_reason" }
    }
    public var choices: [Choice]
    public var usage: TokenUsage?
}

/// Accumulates streamed deltas into a complete assistant turn.
public struct StreamAccumulator: Sendable {
    public private(set) var text = ""
    public private(set) var usage: TokenUsage?
    public private(set) var finishReason: String?
    private var calls: [Int: (id: String, name: String, arguments: String)] = [:]

    public init() {}

    /// Returns the text delta (if any) so the UI can append it.
    @discardableResult
    public mutating func consume(_ chunk: ChatStreamChunk) -> String? {
        if let usage = chunk.usage { self.usage = usage }
        guard let choice = chunk.choices?.first else { return nil }
        if let reason = choice.finishReason { finishReason = reason }
        var appended: String?
        if let content = choice.delta?.content, !content.isEmpty {
            text += content
            appended = content
        }
        for (position, delta) in (choice.delta?.toolCalls ?? []).enumerated() {
            let index = delta.index ?? position
            var entry = calls[index] ?? (id: "", name: "", arguments: "")
            if let id = delta.id, !id.isEmpty { entry.id = id }
            if let name = delta.function?.name { entry.name += name }
            if let args = delta.function?.arguments { entry.arguments += args }
            calls[index] = entry
        }
        return appended
    }

    public var toolCalls: [ToolCall] {
        calls.keys.sorted().compactMap { key in
            guard let c = calls[key], !c.name.isEmpty else { return nil }
            return ToolCall(id: c.id.isEmpty ? "call_\(key)" : c.id, name: c.name, arguments: c.arguments.isEmpty ? "{}" : c.arguments)
        }
    }
}

/// Parses Server-Sent-Event lines from a streamed response.
public enum SSELine: Equatable, Sendable {
    case data(String)
    case done
    case ignore

    public static func parse(_ rawLine: String) -> SSELine {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        guard line.hasPrefix("data:") else { return .ignore }
        var payload = line.dropFirst(5)
        if payload.first == " " { payload = payload.dropFirst() }
        if payload == "[DONE]" { return .done }
        return payload.isEmpty ? .ignore : .data(String(payload))
    }
}

/// Error envelope: `{"error": {"message": "...", "type": "...", "code": "..."}}`.
public struct APIErrorEnvelope: Decodable, Sendable {
    public struct Body: Decodable, Sendable {
        public var message: String?
        public var type: String?
        public var code: String?
    }
    public var error: Body?
}

public struct ModelList: Decodable, Sendable {
    public struct Model: Decodable, Sendable { public var id: String }
    public var data: [Model]
}
