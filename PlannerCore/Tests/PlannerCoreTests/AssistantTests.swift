import XCTest
@testable import PlannerCore

final class AssistantWireTests: XCTestCase {
    func testSSEParsing() {
        XCTAssertEqual(SSELine.parse("data: {\"a\":1}"), .data("{\"a\":1}"))
        XCTAssertEqual(SSELine.parse("data:[DONE]"), .done)
        XCTAssertEqual(SSELine.parse(": keep-alive"), .ignore)
        XCTAssertEqual(SSELine.parse("data: [DONE]\r"), .done)
    }

    func testAccumulatorJoinsToolCallDeltas() {
        var acc = StreamAccumulator()
        acc.consume(ScriptedTransport.chunk(#"{"choices":[{"index":0,"delta":{"content":"Hi"}}]}"#))
        acc.consume(ScriptedTransport.chunk(#"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","function":{"name":"list_","arguments":"{\"st"}}]}}]}"#))
        acc.consume(ScriptedTransport.chunk(#"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"tasks","arguments":"art\":1}"}}]}}]}"#))
        acc.consume(ScriptedTransport.chunk(#"{"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"prompt_tokens_details":{"cached_tokens":4}}}"#))
        XCTAssertEqual(acc.text, "Hi")
        XCTAssertEqual(acc.toolCalls, [ToolCall(id: "call_a", name: "list_tasks", arguments: #"{"start":1}"#)])
        XCTAssertEqual(acc.usage, TokenUsage(promptTokens: 10, completionTokens: 5, cachedTokens: 4))
    }

    func testAssistantToolCallMessageEncodesNullContent() throws {
        let msg = ChatMessage.assistant(nil, toolCalls: [ToolCall(id: "c1", name: "list_tasks", arguments: "{}")])
        let json = String(data: try JSONEncoder().encode(msg), encoding: .utf8)!
        XCTAssertTrue(json.contains(#""content":null"#))
        XCTAssertTrue(json.contains(#""tool_calls""#))
    }

    func testToolDefinitionsAreValidJSON() throws {
        let data = try JSONEncoder().encode(AssistantTool.definitions)
        let parsed = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(parsed.array?.count, AssistantTool.allCases.count)
    }

    func testCompactionKeepsCurrentTurnVerbatim() {
        let wire: [ChatMessage] = [
            .user("first"),
            .assistant(nil, toolCalls: [ToolCall(id: "1", name: "list_tasks", arguments: "{}")]),
            .tool("1", "{rows}"),
            .assistant("Here you go"),
            .user("second"),
            .assistant(nil, toolCalls: [ToolCall(id: "2", name: "list_tasks", arguments: "{}")]),
            .tool("2", "{rows2}"),
        ]
        let compacted = AssistantSession.compact(wire, keepTurns: 10)
        XCTAssertEqual(compacted.map(\.role), [.user, .assistant, .user, .assistant, .tool])
        XCTAssertEqual(compacted[1].content, "Here you go")
        XCTAssertNil(compacted[1].toolCalls)
        XCTAssertEqual(AssistantSession.compact(wire, keepTurns: 1).first?.content, "second")
    }

    func testFallbackModelChoice() {
        XCTAssertEqual(AssistantSession.chooseFallback(from: ["gpt-4.1", "gpt-4.1-mini", "gpt-6-luna", "text-embedding-3-large", "gpt-6-luna-2026-10-01"], unavailable: "gpt-5-mini"), "gpt-6-luna")
        XCTAssertEqual(AssistantSession.chooseFallback(from: ["llama3.1:8b"], unavailable: "gpt-5-mini"), "llama3.1:8b")
    }

    func testTemplatesRender() {
        let plan = PromptTemplate.library.first { $0.id == "plan-day" }!
        XCTAssertEqual(plan.placeholders.first, "date")
        let text = plan.render(["must_dos": "report, gym"])
        XCTAssertTrue(text.contains("Must-dos: report, gym."))
        XCTAssertTrue(text.contains("Plan today from now to 18:00"))
        XCTAssertFalse(text.contains("{"))
        XCTAssertEqual(PromptTemplate.library.count, 12)
        XCTAssertEqual(PromptTemplate.label(for: "nice_to_haves"), "Nice to haves")
    }

    func testLocalTimeCodec() {
        let codec = LocalTimeCodec(calendar: TestClock.calendar)
        XCTAssertEqual(codec.format(TestClock.at(14, 5)), "2026-11-07T14:05")
        XCTAssertEqual(codec.parse("2026-11-07T14:05")?.date, TestClock.at(14, 5))
        XCTAssertEqual(codec.parse("2026-11-07 14:05:00")?.date, TestClock.at(14, 5))
        XCTAssertEqual(codec.parse("2026-11-07")?.hasTime, false)
        XCTAssertNil(codec.parse("tomorrow"))
    }
}

@MainActor
final class AssistantSessionTests: XCTestCase {
    func makeSession(_ store: TaskStore, _ transport: ScriptedTransport, key: String = "sk-test") -> AssistantSession {
        AssistantSession(store: store, environment: AssistantEnvironment(
            transport: transport,
            apiKey: { key },
            settings: { PlannerSettings() },
            now: { TestClock.at(9) }
        ))
    }

    func waitUntilIdle(_ session: AssistantSession) async {
        for _ in 0..<200 {
            await Task.yield()
            if !session.isRunning { try? await Task.sleep(for: .milliseconds(5)); if !session.isRunning { return } }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testReadThenProposeThenApplyAndUndo() async throws {
        let existing = task("Standup", 10, 0, minutes: 15, category: .meeting)
        let (store, _) = await makeStore([existing])
        let transport = ScriptedTransport([
            .tools([("list_tasks", #"{"start":"2026-11-07","end":"2026-11-08"}"#)]),
            .tools([("create_tasks", #"{"summary":"Gym tonight","tasks":[{"title":"Gym","start":"2026-11-07T18:30","duration_minutes":45,"category":"health"}]}"#),
                    ("update_tasks", #"{"updates":[{"id":"t1","start":"2026-11-07T10:30"}]}"#)],
                   text: "Here's a plan."),
        ])
        let session = makeSession(store, transport)
        session.send("Add gym at 6:30 tonight and push standup 30 min")
        await waitUntilIdle(session)

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.requests[0].messages[0].content!.contains("t1|2026-11-07T10:00|15|Standup|meeting|upcoming"))
        // Second request must carry the tool result for list_tasks.
        XCTAssertEqual(transport.requests[1].messages.last?.role, .tool)

        let proposal = try XCTUnwrap(session.items.compactMap { item -> Proposal? in
            if case .proposal(let p) = item.kind { return p } else { return nil }
        }.first)
        XCTAssertEqual(proposal.items.map(\.kind), [.add, .move])
        XCTAssertEqual(proposal.summary, "Gym tonight")
        // Nothing applied yet.
        XCTAssertEqual(store.tasksByID.count, 1)

        session.apply(proposal.id)
        XCTAssertEqual(store.tasksByID.count, 2)
        XCTAssertEqual(store.task(existing.id)?.start, TestClock.at(10, 30))

        session.undo(proposal.id)
        XCTAssertEqual(store.tasksByID.count, 1)
        XCTAssertEqual(store.task(existing.id)?.start, TestClock.at(10))
    }

    func testAskUserPausesUntilAnswered() async throws {
        let (store, _) = await makeStore([])
        let transport = ScriptedTransport([
            .tools([("ask_user", #"{"question":"Morning or afternoon?","options":["Morning","Afternoon"]}"#)]),
            .text("Got it — afternoon."),
        ])
        let session = makeSession(store, transport)
        session.send("Add a dentist appointment tomorrow")
        await waitUntilIdle(session)
        let pending = try XCTUnwrap(session.pendingQuestion)
        XCTAssertEqual(pending.question.options, ["Morning", "Afternoon"])
        XCTAssertEqual(transport.requests.count, 1)

        session.send("Afternoon")  // typing answers the open question
        await waitUntilIdle(session)
        XCTAssertNil(session.pendingQuestion)
        XCTAssertEqual(transport.requests.count, 2)
        let toolMessage = try XCTUnwrap(transport.requests[1].messages.last)
        XCTAssertEqual(toolMessage.role, .tool)
        XCTAssertEqual(toolMessage.toolCallID, "call_0")
        XCTAssertTrue(toolMessage.content!.contains("Afternoon"))
    }

    func testModelFallbackOnModelNotFound() async {
        let (store, _) = await makeStore([])
        let transport = ScriptedTransport([.failure(.modelNotFound("gpt-5-mini")), .text("Hello")])
        let session = makeSession(store, transport)
        var switched: String?
        session.onModelFallback = { switched = $0 }
        session.send("hi")
        await waitUntilIdle(session)
        XCTAssertEqual(switched, "gpt-6-luna")
        XCTAssertEqual(transport.requests.last?.model, "gpt-6-luna")
    }

    func testMissingKeyShowsError() async {
        let (store, _) = await makeStore([])
        let session = makeSession(store, ScriptedTransport([]), key: "")
        session.send("hi")
        await waitUntilIdle(session)
        guard case .error(let message, _) = session.items.last?.kind else { return XCTFail("expected error") }
        XCTAssertTrue(message.contains("API key"))
    }

    func testDiscardReportsBackToModel() async throws {
        let (store, _) = await makeStore([])
        let transport = ScriptedTransport([
            .tools([("create_tasks", #"{"tasks":[{"title":"Read","start":"2026-11-07T20:00","duration_minutes":30}]}"#)]),
            .text("Okay."),
        ])
        let session = makeSession(store, transport)
        session.send("add reading tonight")
        await waitUntilIdle(session)
        let proposal = try XCTUnwrap(session.items.compactMap { item -> Proposal? in
            if case .proposal(let p) = item.kind { return p } else { return nil }
        }.first)
        session.discard(proposal.id)
        session.send("never mind")
        await waitUntilIdle(session)
        let lastUser = transport.requests.last!.messages.last { $0.role == .user }!
        XCTAssertTrue(lastUser.content!.hasPrefix("(App note: User discarded cs_1"))
        XCTAssertTrue(store.tasksByID.isEmpty)
    }

    func testRoutineProposalCreatesSeries() async throws {
        let (store, _) = await makeStore([])
        let transport = ScriptedTransport([
            .tools([("create_tasks", #"{"tasks":[{"title":"Stretch","start":"2026-11-09T07:00","duration_minutes":10,"repeat":{"frequency":"weekdays"}}]}"#)]),
        ])
        let session = makeSession(store, transport)
        session.send("weekday stretch at 7")
        await waitUntilIdle(session)
        let proposal = try XCTUnwrap(session.items.compactMap { item -> Proposal? in
            if case .proposal(let p) = item.kind { return p } else { return nil }
        }.first)
        XCTAssertEqual(proposal.items.first?.kind, .addRoutine)
        session.apply(proposal.id)
        XCTAssertEqual(store.series.count, 1)
        XCTAssertFalse(store.tasksByID.isEmpty)
        session.undo(proposal.id)
        XCTAssertTrue(store.series.isEmpty)
        XCTAssertTrue(store.tasksByID.isEmpty)
    }
}
