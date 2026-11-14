import Foundation
import XCTest
@testable import PlannerCore

// Shared helpers for the assistant QA suites (scenarios, robustness, HTTP end-to-end).

/// A scripted model with explicit tool-call ids, raw-chunk control and a "hang" mode that
/// behaves like `OpenAIHTTPTransport` when the consuming task is cancelled.
final class QAModel: ChatTransport, @unchecked Sendable {
    struct Call: Sendable {
        var id: String
        var name: String
        var args: String
    }

    enum Step: Sendable {
        /// Streams `text` (in two pieces) then each call with its arguments split over 3 deltas.
        case reply(String = "", [Call] = [])
        /// Raw `data:` payloads, streamed as-is.
        case chunks([String])
        case fail(AssistantError)
        /// Streams `text` (and optionally half of a tool call), then waits until cancelled.
        case hang(text: String, partialCall: Call? = nil)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var _requests: [ChatRequest] = []
    private var _listModelsCalls = 0
    private var _hangReached = false
    var models: [String] = ["gpt-4.1-mini", "gpt-6-luna", "text-embedding-3-small"]
    var listModelsError: AssistantError?

    init(_ steps: [Step]) { self.steps = steps }

    var requests: [ChatRequest] { lock.withLock { _requests } }
    var listModelsCalls: Int { lock.withLock { _listModelsCalls } }
    var hangReached: Bool { lock.withLock { _hangReached } }
    var remainingSteps: Int { lock.withLock { steps.count } }

    func push(_ more: [Step]) { lock.withLock { steps += more } }

    /// When set, `listModelInfo` returns these (with shutdown dates) instead of `models`.
    var modelInfos: [ModelInfo]?

    func listModels(endpoint: AssistantEndpoint) async throws -> [String] {
        lock.withLock { _listModelsCalls += 1 }
        if let listModelsError { throw listModelsError }
        return models
    }

    func listModelInfo(endpoint: AssistantEndpoint) async throws -> [ModelInfo] {
        guard let modelInfos else { return try await listModels(endpoint: endpoint).map { ModelInfo(id: $0) } }
        lock.withLock { _listModelsCalls += 1 }
        if let listModelsError { throw listModelsError }
        return modelInfos
    }

    func stream(_ request: ChatRequest, endpoint: AssistantEndpoint) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let step: Step = lock.withLock {
            _requests.append(request)
            return steps.isEmpty ? .reply("(script exhausted)") : steps.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            switch step {
            case .fail(let error):
                continuation.finish(throwing: error)
            case .chunks(let payloads):
                for p in payloads { continuation.yield(Self.chunk(p)) }
                continuation.finish()
            case .reply(let text, let calls):
                for payload in Self.payloads(text: text, calls: calls) { continuation.yield(Self.chunk(payload)) }
                continuation.finish()
            case .hang(let text, let partial):
                if !text.isEmpty { continuation.yield(Self.chunk(SSEPayload.content(text))) }
                if let partial {
                    let half = String(partial.args.prefix(partial.args.count / 2))
                    continuation.yield(Self.chunk(SSEPayload.toolStart(index: 0, id: partial.id, name: partial.name, args: half)))
                }
                self.lock.withLock { self._hangReached = true }
                let waiter = Task {
                    while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
                    // Mirrors OpenAIHTTPTransport: a cancelled request finishes with `.cancelled`.
                    continuation.finish(throwing: AssistantError.cancelled)
                }
                continuation.onTermination = { _ in waiter.cancel() }
            }
        }
    }

    static func payloads(text: String, calls: [Call]) -> [String] {
        var out: [String] = [SSEPayload.role()]
        if !text.isEmpty {
            let mid = text.index(text.startIndex, offsetBy: text.count / 2)
            out.append(SSEPayload.content(String(text[..<mid])))
            out.append(SSEPayload.content(String(text[mid...])))
        }
        for (i, call) in calls.enumerated() {
            let a = call.args
            let third = max(1, a.count / 3)
            let p1 = String(a.prefix(third))
            let p2 = String(a.dropFirst(third).prefix(third))
            let p3 = String(a.dropFirst(2 * third))
            out.append(SSEPayload.toolStart(index: i, id: call.id, name: call.name, args: p1))
            out.append(SSEPayload.toolArgs(index: i, args: p2))
            out.append(SSEPayload.toolArgs(index: i, args: p3))
        }
        out.append(SSEPayload.finish(calls.isEmpty ? "stop" : "tool_calls"))
        out.append(SSEPayload.usage(prompt: 1000, completion: 50, cached: 512))
        return out
    }

    static func chunk(_ json: String) -> ChatStreamChunk {
        try! JSONDecoder().decode(ChatStreamChunk.self, from: Data(json.utf8))
    }
}

/// Builders for OpenAI streaming payloads (the JSON after `data: `).
enum SSEPayload {
    static func quote(_ s: String) -> String {
        String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
    }

    static func role() -> String {
        #"{"id":"chatcmpl-qa","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}],"usage":null}"#
    }

    static func content(_ text: String) -> String {
        #"{"id":"chatcmpl-qa","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"content":\#(quote(text))},"finish_reason":null}],"usage":null}"#
    }

    static func toolStart(index: Int, id: String, name: String, args: String) -> String {
        #"{"id":"chatcmpl-qa","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":\#(index),"id":"\#(id)","type":"function","function":{"name":"\#(name)","arguments":\#(quote(args))}}]},"finish_reason":null}]}"#
    }

    static func toolArgs(index: Int, args: String) -> String {
        #"{"id":"chatcmpl-qa","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":\#(index),"function":{"arguments":\#(quote(args))}}]},"finish_reason":null}]}"#
    }

    static func finish(_ reason: String) -> String {
        #"{"id":"chatcmpl-qa","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{},"finish_reason":"\#(reason)"}]}"#
    }

    static func usage(prompt: Int, completion: Int, cached: Int) -> String {
        #"{"id":"chatcmpl-qa","object":"chat.completion.chunk","created":1,"model":"m","choices":[],"usage":{"prompt_tokens":\#(prompt),"completion_tokens":\#(completion),"total_tokens":\#(prompt + completion),"prompt_tokens_details":{"cached_tokens":\#(cached)}}}"#
    }
}

func call(_ id: String, _ name: String, _ args: String) -> QAModel.Call {
    QAModel.Call(id: id, name: name, args: args)
}

/// Mutable inputs the session reads through its environment closures.
@MainActor
final class QAKnobs {
    var settings: PlannerSettings
    var now: Date
    var apiKey: String?
    init(settings: PlannerSettings, now: Date, apiKey: String?) {
        self.settings = settings
        self.now = now
        self.apiKey = apiKey
    }
}

extension PlannerSettings {
    /// Explicit model + host so the QA suites don't depend on app defaults.
    static func qa(model: String = "gpt-6-luna", baseURL: String = "https://api.openai.com/v1", shareNotes: Bool = false) -> PlannerSettings {
        var s = PlannerSettings()
        s.assistant.model = model
        s.assistant.baseURL = baseURL
        s.assistant.shareNotes = shareNotes
        return s
    }
}

@MainActor
final class QAHarness {
    let store: TaskStore
    let knobs: QAKnobs
    let session: AssistantSession
    let transport: ChatTransport
    private(set) var finishedTurns = 0
    private(set) var reviewFlags: [Bool] = []
    private(set) var fallbacks: [String] = []

    init(store: TaskStore, transport: ChatTransport, settings: PlannerSettings = .qa(), now: Date = TestClock.at(9), apiKey: String? = "sk-test") {
        self.store = store
        self.transport = transport
        let knobs = QAKnobs(settings: settings, now: now, apiKey: apiKey)
        self.knobs = knobs
        session = AssistantSession(store: store, environment: AssistantEnvironment(
            transport: transport,
            apiKey: { knobs.apiKey },
            settings: { knobs.settings },
            uses24HourClock: { true },
            now: { knobs.now }
        ))
        session.onTurnFinished = { [weak self] needsReview in
            self?.finishedTurns += 1
            self?.reviewFlags.append(needsReview)
        }
        session.onModelFallback = { [weak self] model in self?.fallbacks.append(model) }
    }

    var model: QAModel { transport as! QAModel }

    /// Runs `body` and waits until the turn it starts has finished.
    func runTurn(timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line, _ body: () -> Void) async {
        let before = finishedTurns
        body()
        let deadline = Date().addingTimeInterval(timeout)
        while finishedTurns == before {
            if Date() > deadline {
                XCTFail("turn did not finish within \(timeout)s", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    func send(_ text: String, file: StaticString = #filePath, line: UInt = #line) async {
        await runTurn(file: file, line: line) { session.send(text) }
    }

    /// Answers the pending question by tapping a chip (or typing).
    func answer(_ text: String, file: StaticString = #filePath, line: UInt = #line) async {
        guard let pending = session.pendingQuestion else { return XCTFail("no pending question", file: file, line: line) }
        await runTurn(file: file, line: line) { session.answer(pending.itemID, with: text) }
    }

    func waitUntil(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("condition not met", file: file, line: line) }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    // MARK: Items

    var proposals: [Proposal] {
        session.items.compactMap { if case .proposal(let p) = $0.kind { return p } else { return nil } }
    }
    var questions: [AssistantQuestion] {
        session.items.compactMap { if case .question(let q) = $0.kind { return q } else { return nil } }
    }
    var notices: [String] {
        session.items.compactMap { if case .notice(let n) = $0.kind { return n } else { return nil } }
    }
    var errors: [(String, Bool)] {
        session.items.compactMap { if case .error(let m, let r) = $0.kind { return (m, r) } else { return nil } }
    }
    var assistantTexts: [String] {
        session.items.compactMap { if case .assistant(let t) = $0.kind { return t } else { return nil } }
    }
    var userTexts: [String] {
        session.items.compactMap { if case .user(let t) = $0.kind { return t } else { return nil } }
    }
    func proposal(_ id: String) -> Proposal? { proposals.first { $0.id == id } }

    /// Item kinds in order, for asserting chat layout.
    var layout: [String] {
        session.items.map { item in
            switch item.kind {
            case .user: "user"
            case .assistant: "assistant"
            case .question: "question"
            case .proposal: "proposal"
            case .notice: "notice"
            case .error: "error"
            }
        }
    }

    // MARK: Wire

    var requests: [ChatRequest] { model.requests }

    /// Compact signature of a request's messages: `prompt:static`, `prompt:context`, `user:<text>`,
    /// `assistant:<text>[id:name,…]`, `tool:<id>`. System and developer roles both map to `prompt`.
    func signature(_ index: Int, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        guard let r = request(index, file: file, line: line) else { return [] }
        return Self.signature(r.messages)
    }

    /// Request `index`, or nil (with a failure) when the model was called fewer times.
    func request(_ index: Int, file: StaticString = #filePath, line: UInt = #line) -> ChatRequest? {
        let all = requests
        guard all.indices.contains(index) else {
            XCTFail("only \(all.count) requests were sent; wanted #\(index)", file: file, line: line)
            return nil
        }
        return all[index]
    }

    static func signature(_ messages: [ChatMessage]) -> [String] {
        messages.map { m in
            switch m.role {
            case .system, .developer:
                let c = m.content ?? ""
                if c == SystemPrompt.staticPart { return "prompt:static" }
                if c.hasPrefix("CONTEXT") { return "prompt:context" }
                if c.hasPrefix(SystemPrompt.staticPart + "\n\nCONTEXT") { return "prompt:static+context" }
                return "prompt:other"
            case .user:
                return "user:" + (m.content ?? "")
            case .assistant:
                let calls = (m.toolCalls ?? []).map { "\($0.id):\($0.function.name)" }
                return "assistant:" + (m.content ?? "") + (calls.isEmpty ? "" : "[" + calls.joined(separator: ",") + "]")
            case .tool:
                return "tool:" + (m.toolCallID ?? "?")
            }
        }
    }

    /// Content of the tool result for `callID` in request `index`.
    func toolResult(_ index: Int, _ callID: String, file: StaticString = #filePath, line: UInt = #line) -> String? {
        request(index, file: file, line: line)?.messages.first { $0.role == .tool && $0.toolCallID == callID }?.content
    }

    func toolJSON(_ index: Int, _ callID: String, file: StaticString = #filePath, line: UInt = #line) -> JSONValue? {
        toolResult(index, callID, file: file, line: line).flatMap(JSONValue.parse)
    }

    /// The CONTEXT block of request `index`.
    func context(_ index: Int, file: StaticString = #filePath, line: UInt = #line) -> String {
        for m in request(index, file: file, line: line)?.messages ?? [] where m.role == .system || m.role == .developer {
            let c = m.content ?? ""
            if let r = c.range(of: "CONTEXT\n") { return String(c[r.lowerBound...]) }
        }
        return ""
    }

    func lastUserContent(_ index: Int, file: StaticString = #filePath, line: UInt = #line) -> String {
        request(index, file: file, line: line)?.messages.last { $0.role == .user }?.content ?? ""
    }

    /// The whole request as JSON text (what would go over the wire).
    func requestJSON(_ index: Int, file: StaticString = #filePath, line: UInt = #line) -> String {
        request(index, file: file, line: line).map(Self.encode) ?? ""
    }

    static func encode(_ request: ChatRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: try! encoder.encode(request), encoding: .utf8)!
    }

    /// Every wire message is valid for Chat Completions: each assistant tool call is answered
    /// exactly once, by tool messages directly after it, before the next user message.
    static func assertWireIsValid(_ messages: [ChatMessage], allowPendingTail: Set<String> = [], file: StaticString = #filePath, line: UInt = #line) {
        var i = 0
        while i < messages.count {
            let m = messages[i]
            if m.role == .assistant {
                if (m.toolCalls ?? []).isEmpty {
                    XCTAssertFalse((m.content ?? "").isEmpty, "assistant message without content or tool calls", file: file, line: line)
                }
                if let calls = m.toolCalls, !calls.isEmpty {
                    var answered: [String] = []
                    var j = i + 1
                    while j < messages.count, messages[j].role == .tool {
                        answered.append(messages[j].toolCallID ?? "")
                        j += 1
                    }
                    let expected = Set(calls.map(\.id))
                    let isTail = j == messages.count
                    let missing = expected.subtracting(answered)
                    if !(isTail && missing.isSubset(of: allowPendingTail)) {
                        XCTAssertEqual(Set(answered), expected, "tool calls answered after assistant #\(i)", file: file, line: line)
                    }
                    XCTAssertEqual(answered.count, Set(answered).count, "a tool call was answered twice", file: file, line: line)
                    i = j
                    continue
                }
            }
            if m.role == .tool {
                XCTFail("orphan tool message \(m.toolCallID ?? "?") at #\(i)", file: file, line: line)
            }
            i += 1
        }
    }
}
