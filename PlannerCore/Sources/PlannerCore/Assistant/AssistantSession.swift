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
    /// Read-only external calendar events (Apple Calendar) overlapping an interval.
    public var busyBlocks: @MainActor @Sendable (DateInterval) -> [BusyBlock]

    public init(
        transport: ChatTransport,
        apiKey: @escaping @MainActor @Sendable () -> String?,
        settings: @escaping @MainActor @Sendable () -> PlannerSettings,
        uses24HourClock: @escaping @MainActor @Sendable () -> Bool = { true },
        now: @escaping @MainActor @Sendable () -> Date = { Date() },
        busyBlocks: @escaping @MainActor @Sendable (DateInterval) -> [BusyBlock] = { _ in [] }
    ) {
        self.transport = transport
        self.apiKey = apiKey
        self.settings = settings
        self.uses24HourClock = uses24HourClock
        self.now = now
        self.busyBlocks = busyBlocks
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
    /// `reasoning_effort` to send instead of the computed one, per model (after a 400 about it).
    @ObservationIgnored private var effortOverrides: [String: String] = [:]
    /// A model picked because `configured` wasn't available. Ignored once the user picks another.
    @ObservationIgnored private var fallback: (configured: String, effective: String)?
    /// Bumped by `clear()` so a turn that is still winding down can't write into the new chat.
    @ObservationIgnored private var epoch = 0

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
        epoch &+= 1
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
        var result: [String: JSONValue] = ["answer": .string(text)]
        if !pendingNotes.isEmpty {
            // e.g. the user applied the card shown next to this question while it was open.
            result["app_note"] = .string(pendingNotes.joined(separator: " "))
            pendingNotes.removeAll()
        }
        wire.append(.tool(q.callID, JSONValue.object(result).serialized()))
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
        let executor = ToolExecutor(store: store, settings: env.settings(), now: env.now(), shareNotes: false, busy: env.busyBlocks)
        let result = executor.apply(proposal)
        mutateProposal(proposalID) { p in
            p.state = .applied(count: result.count, total: p.items.count)
            p.undoEntryID = result.undoID
            p.createdSeriesIDs = result.series
        }
        // Titles are data: quoted and flattened so a title can't add lines to the user's message.
        let titles = proposal.items.filter(\.isSelected).compactMap { ($0.after ?? $0.before)?.title }.prefix(6).map(Self.quoted)
        var note = "User applied \(proposalID) (\(result.count) of \(proposal.items.count) changes: \(titles.joined(separator: ", ")))."
        if !result.skipped.isEmpty {
            note += " Skipped because they had already started or changed: \(result.skipped.map(Self.quoted).joined(separator: ", "))."
            items.append(ChatItem(.notice("Skipped \(result.skipped.joined(separator: ", ")) — already started or changed.")))
        }
        pendingNotes.append(note)
        changed()
    }

    /// `"Title"` on one line, at most 60 characters, for App notes.
    nonisolated static func quoted(_ title: String) -> String {
        let flat = ToolExecutor.flatten(title).replacingOccurrences(of: "\"", with: "'")
        return "\"" + (flat.count > 60 ? String(flat.prefix(59)) + "…" : flat) + "\""
    }

    public func discard(_ proposalID: String) {
        guard let proposal = proposal(proposalID), proposal.state == .pending else { return }
        mutateProposal(proposalID) { $0.state = .discarded }
        pendingNotes.append("User discarded \(proposalID); nothing was changed.")
        changed()
    }

    public func undo(_ proposalID: String) {
        guard let proposal = proposal(proposalID), case .applied = proposal.state else { return }
        // Tasks this card added that the user has since started stay (the store never deletes a
        // running task on a plan-level undo).
        let kept = proposal.items.filter { $0.kind == .add }.compactMap { $0.after.flatMap { store.task($0.id) } }.filter(\.status.isActive)
        if let entry = proposal.undoEntryID, !store.undo(entry, now: env.now()) {
            // The store only keeps the last 20 undo steps (or it was undone from elsewhere).
            items.append(ChatItem(.notice("That change can't be undone any more."), date: env.now()))
            changed()
            return
        }
        for seriesID in proposal.createdSeriesIDs { store.removeSeries(seriesID) }
        mutateProposal(proposalID) { $0.state = .undone }
        var note = "User undid \(proposalID); those changes were reverted."
        if !kept.isEmpty {
            note += " Kept \(kept.map { Self.quoted($0.title) }.joined(separator: ", ")) because it is running."
            items.append(ChatItem(.notice("Kept \(kept.map(\.title).joined(separator: ", ")) — it's already running."), date: env.now()))
        }
        pendingNotes.append(note)
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
        var roundsLeft = maxRounds
        var hitRoundLimit = false
        let turnEpoch = epoch

        rounds: while true {
            if Task.isCancelled { break }
            guard roundsLeft > 0 else { hitRoundLimit = true; break }
            roundsLeft -= 1
            let now = env.now()
            let model = currentModel(settings)
            let capabilities = ModelCapabilities.for(model)
            if !capabilities.supportsChatTools {
                let message = "“\(model)” can't use the assistant's tools through Chat Completions. Pick a tool-capable model (for example \(AssistantSettings.defaultModel)) in Settings › Assistant."
                items.append(ChatItem(.error(message, retryable: false), date: now))
                break rounds
            }
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
                // A cancelled consumer sees the stream end *normally* (AsyncThrowingStream returns
                // nil on cancellation), so a Stop mid-reply must be detected here, not in `catch`.
                if Task.isCancelled { throw AssistantError.cancelled }
                streamingText = acc.text
            } catch let error as AssistantError {
                if error == .cancelled || Task.isCancelled {
                    // After clear() the conversation is gone: write nothing into the new one.
                    if turnEpoch == epoch {
                        if !acc.text.isEmpty { commitAssistantText(acc.text + " …") }
                        items.append(ChatItem(.notice("Stopped.")))
                        rollBackDanglingToolCalls()
                    }
                    break rounds
                }
                if case .modelNotFound = error, !attemptedFallback {
                    attemptedFallback = true
                    let replacement = await pickFallbackModel(endpoint: endpoint, unavailable: model)
                    if Task.isCancelled { break rounds }
                    if let replacement {
                        fallback = (configured: settings.assistant.model, effective: replacement)
                        onModelFallback?(replacement)
                        items.append(ChatItem(.notice("“\(model)” isn't available, so I switched to \(replacement).")))
                        continue rounds
                    }
                }
                if case .server(400, let message) = error, let param = Self.unsupportedParameter(in: message),
                   recoverFromUnsupported(param, model: model, sentEffort: request.reasoningEffort) {
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
            if acc.text.isEmpty, calls.isEmpty {
                // Nothing to show and nothing to send back: an assistant message with neither
                // content nor tool calls is invalid on the next request.
                let message = acc.finishReason == "length"
                    ? "The reply hit the output limit before any text arrived. Tap Retry."
                    : "The model sent an empty reply. Tap Retry."
                items.append(ChatItem(.error(message, retryable: true), date: now))
                break rounds
            }
            wire.append(.assistant(acc.text.isEmpty ? nil : acc.text, toolCalls: calls))
            if !acc.text.isEmpty { commitAssistantText(acc.text) }
            streamingText = ""
            if calls.isEmpty { break rounds }

            var needsFollowUp = false
            var askedQuestion = false
            let executor = ToolExecutor(store: store, settings: settings, now: now, shareNotes: settings.assistant.shareNotes,
                                    busy: env.busyBlocks, shareEventTitles: settings.assistant.shareEventTitles)
            for call in calls {
                guard let tool = AssistantTool(rawValue: call.function.name) else {
                    let names = AssistantTool.allCases.map(\.rawValue).joined(separator: ", ")
                    wire.append(.tool(call.id, (["status": "error", "code": "unknown_tool", "message": .string("Available tools: \(names).")] as JSONValue).serialized()))
                    needsFollowUp = true
                    continue
                }
                guard let args = JSONValue.parse(call.function.arguments), case .object = args else {
                    wire.append(.tool(call.id, (["status": "error", "code": "bad_arguments", "message": "Arguments must be one JSON object matching the tool's schema. Nothing was staged."] as JSONValue).serialized()))
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
        guard turnEpoch == epoch else { return }
        // A proposal staged in the final round (e.g. loop limit) still needs to be shown.
        if let d = draft, !d.items.isEmpty { items.append(ChatItem(.proposal(d), date: env.now())) }
        if hitRoundLimit {
            items.append(ChatItem(.notice("I stopped after \(maxRounds) steps without finishing. Try a more specific request."), date: env.now()))
        }
    }

    /// The model to use: a fallback only while the user still has the model it replaced.
    private func currentModel(_ settings: PlannerSettings) -> String {
        if let fallback, fallback.configured == settings.assistant.model { return fallback.effective }
        return settings.assistant.model
    }

    /// Handles a 400 that names an unsupported parameter. Returns true to retry the round.
    private func recoverFromUnsupported(_ param: String, model: String, sentEffort: String?) -> Bool {
        if param == "reasoning_effort" {
            let caps = ModelCapabilities.for(model)
            if caps.forcedEffort != nil || caps.allowedEfforts.contains("none") {
                // Dropping the parameter means the API default ("medium"), which can't call tools
                // on GPT-6 Luna/Sol. Retry once with "none"; if "none" itself is refused, give up.
                guard sentEffort != "none", effortOverrides[model] == nil else { return false }
                effortOverrides[model] = "none"
                return true
            }
        }
        return dropParam(param, for: model)
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
        let executor = ToolExecutor(store: store, settings: settings, now: now, shareNotes: settings.assistant.shareNotes,
                                    busy: env.busyBlocks, shareEventTitles: settings.assistant.shareEventTitles)
        let today = DayKey(now, calendar: store.calendar)
        let todayRows = store.tasks(on: today).map { executor.row(for: $0, refs: &refs) }
        var tomorrowRows: [String]?
        if settings.assistant.contextDays > 1 {
            tomorrowRows = store.tasks(on: today.adding(days: 1, calendar: store.calendar)).map { executor.row(for: $0, refs: &refs) }
        }
        let activeRow = store.activeTask.map { executor.row(for: $0, refs: &refs) }
        let eventRows = executor.eventRows(in: today.interval(calendar: store.calendar))
        let context = SystemPrompt.context(.init(
            now: now, calendar: store.calendar, uses24HourClock: env.uses24HourClock(), settings: settings,
            activeTaskRow: activeRow, todayRows: todayRows, tomorrowRows: tomorrowRows, eventRows: eventRows
        ))
        let history = Self.compact(wire, keepTurns: keepTurns)
        let capabilities = ModelCapabilities.for(model)
        var messages: [ChatMessage]
        if endpoint.isOpenAI {
            // Static prompt + tools + history form a stable, cacheable prefix; the changing
            // CONTEXT goes right before the latest user turn, in the same role as the prompt
            // (`developer` for o1 and newer, which replaces `system`).
            let role: ChatMessage.Role = capabilities.usesDeveloperRole ? .developer : .system
            let lastUser = history.lastIndex(where: { $0.role == .user }) ?? history.endIndex
            messages = [ChatMessage(role: role, content: SystemPrompt.staticPart)]
            messages += history[..<lastUser]
            messages.append(ChatMessage(role: role, content: context))
            messages += history[lastUser...]
        } else {
            // Many local servers only accept one leading system message.
            messages = [ChatMessage.system(SystemPrompt.staticPart + "\n\n" + context)] + history
        }
        let dropped = droppedParams[model] ?? []
        var effort: String?
        if endpoint.acceptsReasoningEffort, !dropped.contains("reasoning_effort") {
            effort = effortOverrides[model] ?? capabilities.effort(forRequested: settings.assistant.reasoningEffort)
        }
        return ChatRequest(
            model: model,
            messages: messages,
            tools: AssistantTool.definitions,
            stream: true,
            streamOptions: endpoint.isOpenAI && !dropped.contains("stream_options") ? .init(includeUsage: true) : nil,
            maxCompletionTokens: endpoint.isOpenAI && !dropped.contains("max_completion_tokens") ? 3000 : nil,
            reasoningEffort: effort,
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

    /// Picks a replacement model from the live `/models` list.
    private func pickFallbackModel(endpoint: AssistantEndpoint, unavailable: String) async -> String? {
        guard let models = try? await env.transport.listModelInfo(endpoint: endpoint), !models.isEmpty else { return nil }
        return Self.chooseFallback(from: models, unavailable: unavailable, now: env.now())
    }

    public nonisolated static func chooseFallback(from models: [String], unavailable: String) -> String? {
        chooseFallback(from: models.map { ModelInfo(id: $0) }, unavailable: unavailable, now: Date())
    }

    /// Only tool-capable chat models that aren't shut down (or shutting down within 30 days) and
    /// aren't premium/chat-tuned variants. Among `gpt-*` ids: the small tier (luna/mini, then
    /// nano), then the newest version, then the shortest id (base alias over dated snapshot).
    /// Other ids (local servers) keep the list's order. Nil when nothing is usable.
    public nonisolated static func chooseFallback(from models: [ModelInfo], unavailable: String, now: Date) -> String? {
        let horizon = now.addingTimeInterval(30 * 86_400)
        let usable = models.filter { model in
            let id = model.id.lowercased()
            guard id != unavailable.lowercased() else { return false }
            if let shutdown = model.shutdownDate, shutdown <= horizon { return false }
            guard ModelCapabilities.for(model.id).supportsChatTools else { return false }
            return !["-pro", "chat-latest"].contains(where: id.contains)
        }
        func score(_ id: String) -> (Int, Int, Int, Int, String) {
            let m = id.lowercased()
            let tier = (m.contains("luna") || m.contains("mini")) ? 0 : m.contains("nano") ? 1 : 2
            let version = m.dropFirst(4).prefix(while: { $0.isNumber || $0 == "." }).split(separator: ".")
            let major = version.first.flatMap { Int($0) } ?? 0
            let minor = version.dropFirst().first.flatMap { Int($0) } ?? 0
            return (tier, -major, -minor, m.count, m)
        }
        let gpt = usable.filter { $0.id.lowercased().hasPrefix("gpt-") }.sorted { score($0.id) < score($1.id) }
        return (gpt.first ?? usable.first)?.id
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
