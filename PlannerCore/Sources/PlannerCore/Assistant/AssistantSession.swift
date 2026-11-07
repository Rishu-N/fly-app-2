import Foundation
import Observation

public struct AssistantQuestion: Codable, Hashable, Sendable {
    public var callID: String
    public var text: String
    public var options: [String]
    public var allowFreeText: Bool
    public var answer: String?
}

public struct ChatItem: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case user(String)
        case assistant(String)
        case question(AssistantQuestion)
        case proposal(Proposal)
        case notice(String)
        case error(String, retryable: Bool)
    }

    public var id: UUID
    public var date: Date
    public var kind: Kind

    public init(_ kind: Kind, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.kind = kind
    }
}

/// Everything needed to restore a conversation after relaunch.
public struct AssistantTranscript: Codable, Sendable {
    public var items: [ChatItem] = []
    public var wire: [ChatMessage] = []
    public var refs = TaskRefRegistry()
    public var usage = TokenUsage()
    public var proposalCounter = 0
    public var pendingNotes: [String] = []
    public init() {}
}

/// Dependencies injected by the app.
public struct AssistantEnvironment: Sendable {
    public var transport: ChatTransport
    public var apiKey: @MainActor @Sendable () -> String?
    public var settings: @MainActor @Sendable () -> PlannerSettings
    public var uses24HourClock: @MainActor @Sendable () -> Bool
    public var now: @MainActor @Sendable () -> Date

    public init(
        transport: ChatTransport,
        apiKey: @escaping @MainActor @Sendable () -> String?,
        settings: @escaping @MainActor @Sendable () -> PlannerSettings,
        uses24HourClock: @escaping @MainActor @Sendable () -> Bool = { true },
        now: @escaping @MainActor @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.apiKey = apiKey
        self.settings = settings
        self.uses24HourClock = uses24HourClock
        self.now = now
    }
}

/// The on-device agent loop: stream a reply, run read tools, stage write tools as a reviewable
/// proposal, pause on `ask_user`, and never apply anything without the user's tap.
@MainActor
@Observable
public final class AssistantSession {
    public private(set) var items: [ChatItem] = []
    public private(set) var isRunning = false
    /// Partial text of the reply currently streaming in (shown as a live bubble).
    public private(set) var streamingText = ""
    public private(set) var statusLine: String?
    public private(set) var usage = TokenUsage()

    /// Max model round-trips per user message.
    @ObservationIgnored public var maxRounds = 6
    @ObservationIgnored public var keepTurns = 10
    @ObservationIgnored public var onModelFallback: (@MainActor (String) -> Void)?
    @ObservationIgnored public var onTranscriptChange: (@MainActor () -> Void)?
    /// Called when a turn ends; `needsReview` is true when a proposal or question awaits the user.
    @ObservationIgnored public var onTurnFinished: (@MainActor (_ needsReview: Bool) -> Void)?

    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private let env: AssistantEnvironment
    @ObservationIgnored private var wire: [ChatMessage] = []
    @ObservationIgnored private var refs = TaskRefRegistry()
    @ObservationIgnored private var proposalCounter = 0
    @ObservationIgnored private var pendingNotes: [String] = []
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var droppedParams: [String: Set<String>] = [:]
    @ObservationIgnored private var modelOverride: String?

    public init(store: TaskStore, environment: AssistantEnvironment, transcript: AssistantTranscript? = nil) {
        self.store = store
        self.env = environment
        if let transcript { restore(transcript) }
    }

    // MARK: Public API

    public var pendingQuestion: (itemID: UUID, question: AssistantQuestion)? {
        for item in items.reversed() {
            if case .question(let q) = item.kind, q.answer == nil { return (item.id, q) }
        }
        return nil
    }

    public var hasPendingProposal: Bool {
        items.contains { if case .proposal(let p) = $0.kind { return p.state == .pending }; return false }
    }

    public var transcript: AssistantTranscript {
        var t = AssistantTranscript()
        t.items = items
        t.wire = wire
        t.refs = refs
        t.usage = usage
        t.proposalCounter = proposalCounter
        t.pendingNotes = pendingNotes
        return t
    }

    public func restore(_ t: AssistantTranscript) {
        items = t.items
        wire = t.wire
        refs = t.refs
        usage = t.usage
        proposalCounter = t.proposalCounter
        pendingNotes = t.pendingNotes
    }

    public func clear() {
        stop()
        items = []
        wire = []
        refs = TaskRefRegistry()
        proposalCounter = 0
        pendingNotes = []
        changed()
    }

    /// Sends a user message. If a question is pending, the text answers it.
    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        if let pending = pendingQuestion {
            answer(pending.itemID, with: trimmed)
            return
        }
        items.append(ChatItem(.user(trimmed), date: env.now()))
        var content = trimmed
        if !pendingNotes.isEmpty {
            content = "(App note: " + pendingNotes.joined(separator: " ") + ")\n\n" + trimmed
            pendingNotes.removeAll()
        }
        wire.append(.user(content))
        changed()
        start()
    }

    /// Answers a pending `ask_user` question and resumes the loop.
    public func answer(_ itemID: UUID, with text: String) {
        guard !isRunning, let index = items.firstIndex(where: { $0.id == itemID }),
              case .question(var q) = items[index].kind, q.answer == nil else { return }
        q.answer = text
        items[index].kind = .question(q)
        items.append(ChatItem(.user(text), date: env.now()))
        wire.append(.tool(q.callID, (["answer": .string(text)] as JSONValue).serialized()))
        // Any other unanswered questions from the same turn are closed so the wire stays valid.
        for i in items.indices {
            if case .question(var other) = items[i].kind, other.answer == nil {
                other.answer = "(skipped)"
                items[i].kind = .question(other)
                wire.append(.tool(other.callID, #"{"answer":"(skipped — ask one question at a time)"}"#))
            }
        }
        changed()
        start()
    }

    public func toggle(_ itemID: UUID, inProposal proposalID: String) {
        mutateProposal(proposalID) { p in
            guard p.state == .pending, let i = p.items.firstIndex(where: { $0.id == itemID }) else { return }
            p.items[i].isSelected.toggle()
        }
    }

    public func apply(_ proposalID: String) {
        guard let proposal = proposal(proposalID), proposal.state == .pending else { return }
        let executor = ToolExecutor(store: store, settings: env.settings(), now: env.now(), shareNotes: false)
        let result = executor.apply(proposal)
        mutateProposal(proposalID) { p in
            p.state = .applied(count: result.count, total: p.items.count)
            p.undoEntryID = result.undoID
            p.createdSeriesIDs = result.series
        }
        let titles = proposal.items.filter(\.isSelected).compactMap { ($0.after ?? $0.before)?.title }.prefix(6)
        pendingNotes.append("User applied \(proposalID) (\(result.count) of \(proposal.items.count) changes: \(titles.joined(separator: ", "))).")
        changed()
    }

    public func discard(_ proposalID: String) {
        guard let proposal = proposal(proposalID), proposal.state == .pending else { return }
        mutateProposal(proposalID) { $0.state = .discarded }
        pendingNotes.append("User discarded \(proposalID); nothing was changed.")
        changed()
    }

    public func undo(_ proposalID: String) {
        guard let proposal = proposal(proposalID), case .applied = proposal.state else { return }
        if let entry = proposal.undoEntryID { store.undo(entry, now: env.now()) }
        for seriesID in proposal.createdSeriesIDs { store.removeSeries(seriesID) }
        mutateProposal(proposalID) { $0.state = .undone }
        pendingNotes.append("User undid \(proposalID); those changes were reverted.")
        changed()
    }

    public func stop() {
        runTask?.cancel()
        runTask = nil
    }

    /// Re-runs the last turn after an error.
    public func retry() {
        guard !isRunning else { return }
        if let last = items.last, case .error = last.kind { items.removeLast() }
        start()
    }

    // MARK: Loop

    private func start() {
        runTask?.cancel()
        runTask = Task { [weak self] in await self?.runLoop() }
    }

    private func runLoop() async {
        isRunning = true
        statusLine = "Thinking…"
        defer {
            isRunning = false
            statusLine = nil
            streamingText = ""
            changed()
            onTurnFinished?(pendingQuestion != nil || hasPendingProposal)
        }

        let settings = env.settings()
        let endpoint: AssistantEndpoint
        do {
            endpoint = try AssistantEndpoint(baseURLString: settings.assistant.baseURL, apiKey: env.apiKey() ?? "")
        } catch {
            items.append(ChatItem(.error(AssistantError.invalidBaseURL.userMessage, retryable: false)))
            return
        }
        if endpoint.isOpenAI, endpoint.apiKey.isEmpty {
            items.append(ChatItem(.error(AssistantError.missingAPIKey.userMessage, retryable: false)))
            return
        }

        var draft: Proposal?
        var attemptedFallback = false
        var retriesLeft = 1

        rounds: for _ in 0..<maxRounds {
            if Task.isCancelled { break }
            let now = env.now()
            let model = modelOverride ?? settings.assistant.model
            let request = buildRequest(model: model, settings: settings, endpoint: endpoint, now: now)

            var acc = StreamAccumulator()
            do {
                streamingText = ""
                var lastPublish = Date.distantPast
                for try await chunk in env.transport.stream(request, endpoint: endpoint) {
                    if acc.consume(chunk) != nil {
                        let t = Date()
                        if t.timeIntervalSince(lastPublish) > 0.04 {
                            streamingText = acc.text
                            statusLine = nil
                            lastPublish = t
                        }
                    }
                }
                streamingText = acc.text
            } catch let error as AssistantError {
                if error == .cancelled || Task.isCancelled {
                    if !acc.text.isEmpty { commitAssistantText(acc.text + " …") }
                    items.append(ChatItem(.notice("Stopped.")))
                    rollBackDanglingToolCalls()
                    break rounds
                }
                if case .modelNotFound = error, !attemptedFallback {
                    attemptedFallback = true
                    if let fallback = await pickFallbackModel(endpoint: endpoint, unavailable: model) {
                        modelOverride = fallback
                        onModelFallback?(fallback)
                        items.append(ChatItem(.notice("“\(model)” isn't available, so I switched to \(fallback).")))
                        continue rounds
                    }
                }
                if case .server(400, let message) = error, let param = Self.unsupportedParameter(in: message), dropParam(param, for: model) {
                    continue rounds
                }
                if error.isRetryable, retriesLeft > 0 {
                    retriesLeft -= 1
                    var delay: TimeInterval = 1.5
                    if case .rateLimited(let after) = error, let after { delay = min(10, max(1, after)) }
                    statusLine = "Retrying…"
                    try? await Task.sleep(for: .seconds(delay))
                    continue rounds
                }
                items.append(ChatItem(.error(error.userMessage, retryable: error.isRetryable)))
                break rounds
            } catch {
                items.append(ChatItem(.error(AssistantError.network(error.localizedDescription).userMessage, retryable: true)))
                break rounds
            }

            if let u = acc.usage { usage = usage + u }
            let calls = acc.toolCalls
            wire.append(.assistant(acc.text.isEmpty ? nil : acc.text, toolCalls: calls))
            if !acc.text.isEmpty { commitAssistantText(acc.text) }
            streamingText = ""
            if calls.isEmpty { break rounds }

            var needsFollowUp = false
            var askedQuestion = false
            let executor = ToolExecutor(store: store, settings: settings, now: now, shareNotes: settings.assistant.shareNotes)
            for call in calls {
                let args = JSONValue.parse(call.function.arguments) ?? [:]
                guard let tool = AssistantTool(rawValue: call.function.name) else {
                    wire.append(.tool(call.id, #"{"status":"error","code":"unknown_tool"}"#))
                    needsFollowUp = true
                    continue
                }
                statusLine = tool.statusLine
                switch tool {
                case .listTasks:
                    wire.append(.tool(call.id, executor.listTasks(args, refs: &refs)))
                    needsFollowUp = true
                case .findFreeSlots:
                    wire.append(.tool(call.id, executor.findFreeSlots(args)))
                    needsFollowUp = true
                case .createTasks, .updateTasks, .shiftTasks, .deleteTasks:
                    if draft == nil {
                        proposalCounter += 1
                        draft = Proposal(id: "cs_\(proposalCounter)")
                    }
                    let result = executor.stage(tool, args: args, into: &draft!, refs: &refs)
                    wire.append(.tool(call.id, result))
                    if result.contains(#""status":"error""#) || result.contains(#""errors":"#) { needsFollowUp = true }
                case .askUser:
                    if askedQuestion {
                        wire.append(.tool(call.id, #"{"answer":"(skipped — ask one question at a time)"}"#))
                        continue
                    }
                    askedQuestion = true
                    let options = (args["options"]?.array ?? []).compactMap(\.string).prefix(4)
                    let q = AssistantQuestion(
                        callID: call.id,
                        text: args["question"]?.string ?? "Could you clarify?",
                        options: Array(options),
                        allowFreeText: args["allow_free_text"]?.bool ?? true,
                        answer: nil
                    )
                    items.append(ChatItem(.question(q), date: now))
                }
            }

            if let d = draft, !d.items.isEmpty, !needsFollowUp || askedQuestion {
                items.append(ChatItem(.proposal(d), date: now))
                draft = nil
            }
            changed()
            if askedQuestion { break rounds }
            if !needsFollowUp { break rounds }
        }
        // A proposal staged in the final round (e.g. loop limit) still needs to be shown.
        if let d = draft, !d.items.isEmpty { items.append(ChatItem(.proposal(d), date: env.now())) }
    }

    private func commitAssistantText(_ text: String) {
        items.append(ChatItem(.assistant(text.trimmingCharacters(in: .whitespacesAndNewlines)), date: env.now()))
    }

    /// If a turn is cancelled between an assistant tool-call message and its tool results, the
    /// wire would be invalid. Add placeholder results.
    private func rollBackDanglingToolCalls() {
        guard let lastAssistant = wire.lastIndex(where: { $0.role == .assistant }), let calls = wire[lastAssistant].toolCalls else { return }
        let answered = Set(wire[(lastAssistant + 1)...].compactMap(\.toolCallID))
        let pendingQuestionIDs = Set(items.compactMap { item -> String? in
            if case .question(let q) = item.kind, q.answer == nil { return q.callID }
            return nil
        })
        for call in calls where !answered.contains(call.id) && !pendingQuestionIDs.contains(call.id) {
            wire.append(.tool(call.id, #"{"status":"cancelled"}"#))
        }
    }

    // MARK: Request building

    func buildRequest(model: String, settings: PlannerSettings, endpoint: AssistantEndpoint, now: Date) -> ChatRequest {
        let executor = ToolExecutor(store: store, settings: settings, now: now, shareNotes: settings.assistant.shareNotes)
        let today = DayKey(now, calendar: store.calendar)
        let todayRows = store.tasks(on: today).map { executor.row(for: $0, refs: &refs) }
        var tomorrowRows: [String]?
        if settings.assistant.contextDays > 1 {
            tomorrowRows = store.tasks(on: today.adding(days: 1, calendar: store.calendar)).map { executor.row(for: $0, refs: &refs) }
        }
        let activeRow = store.activeTask.map { executor.row(for: $0, refs: &refs) }
        let system = SystemPrompt.build(.init(
            now: now, calendar: store.calendar, uses24HourClock: env.uses24HourClock(), settings: settings,
            activeTaskRow: activeRow, todayRows: todayRows, tomorrowRows: tomorrowRows
        ))
        let messages = [ChatMessage.system(system)] + Self.compact(wire, keepTurns: keepTurns)
        let dropped = droppedParams[model] ?? []
        let reasoning = Self.isReasoningModel(model) && endpoint.isOpenAI && !dropped.contains("reasoning_effort")
        return ChatRequest(
            model: model,
            messages: messages,
            tools: AssistantTool.definitions,
            stream: true,
            streamOptions: endpoint.isOpenAI && !dropped.contains("stream_options") ? .init(includeUsage: true) : nil,
            maxCompletionTokens: endpoint.isOpenAI && !dropped.contains("max_completion_tokens") ? 3000 : nil,
            reasoningEffort: reasoning ? settings.assistant.reasoningEffort : nil,
            parallelToolCalls: nil,
            user: nil
        )
    }

    /// Keeps the current turn verbatim; earlier turns keep only user text and assistant prose
    /// (tool payloads dropped), capped at `keepTurns` turns.
    nonisolated static func compact(_ wire: [ChatMessage], keepTurns: Int) -> [ChatMessage] {
        let userIndices = wire.indices.filter { wire[$0].role == .user }
        guard let currentStart = userIndices.last else { return wire }
        let earlierStarts = userIndices.dropLast().suffix(max(0, keepTurns - 1))
        var result: [ChatMessage] = []
        if let firstKept = earlierStarts.first {
            for message in wire[firstKept..<currentStart] {
                switch message.role {
                case .user:
                    result.append(message)
                case .assistant:
                    if let text = message.content, !text.isEmpty { result.append(.assistant(text)) }
                default:
                    continue
                }
            }
        }
        result.append(contentsOf: wire[currentStart...])
        return result
    }

    nonisolated static func isReasoningModel(_ model: String) -> Bool {
        let m = model.lowercased()
        return m.hasPrefix("gpt-5") || m.hasPrefix("gpt-6") || m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4")
    }

    nonisolated static func unsupportedParameter(in message: String) -> String? {
        let lower = message.lowercased()
        for param in ["reasoning_effort", "max_completion_tokens", "stream_options"] where lower.contains(param) {
            return param
        }
        return nil
    }

    private func dropParam(_ param: String, for model: String) -> Bool {
        var set = droppedParams[model] ?? []
        guard !set.contains(param) else { return false }
        set.insert(param)
        droppedParams[model] = set
        return true
    }

    /// Picks a replacement model from the live `/models` list: same family first, then any
    /// small chat model, then anything chat-capable.
    private func pickFallbackModel(endpoint: AssistantEndpoint, unavailable: String) async -> String? {
        guard let models = try? await env.transport.listModels(endpoint: endpoint), !models.isEmpty else { return nil }
        return Self.chooseFallback(from: models, unavailable: unavailable)
    }

    public nonisolated static func chooseFallback(from models: [String], unavailable: String) -> String? {
        let chat = models.filter { id in
            let m = id.lowercased()
            let excluded = ["embedding", "whisper", "tts", "dall-e", "image", "audio", "realtime", "transcribe", "moderation", "search", "codex"]
            return m.hasPrefix("gpt-") && !excluded.contains(where: m.contains) && m != unavailable.lowercased()
        }
        func score(_ id: String) -> (Int, Int, String) {
            let m = id.lowercased()
            let small = (m.contains("mini") || m.contains("luna") || m.contains("nano")) ? 0 : 1
            let version = Int(m.dropFirst(4).prefix(while: \.isNumber)) ?? 0
            // Prefer small, then newest major version, then shortest (base alias over dated snapshot).
            return (small, -version, String(repeating: "z", count: m.count))
        }
        let sorted = chat.sorted { score($0) < score($1) }
        return sorted.first ?? models.first(where: { $0 != unavailable })
    }

    // MARK: Helpers

    private func proposal(_ id: String) -> Proposal? {
        for item in items {
            if case .proposal(let p) = item.kind, p.id == id { return p }
        }
        return nil
    }

    private func mutateProposal(_ id: String, _ body: (inout Proposal) -> Void) {
        for i in items.indices {
            if case .proposal(var p) = items[i].kind, p.id == id {
                body(&p)
                items[i].kind = .proposal(p)
                return
            }
        }
    }

    private func changed() {
        onTranscriptChange?()
    }
}
