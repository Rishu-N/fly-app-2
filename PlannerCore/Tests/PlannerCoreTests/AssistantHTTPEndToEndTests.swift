import XCTest
@testable import PlannerCore

/// Real HTTP: `OpenAIHTTPTransport` + `AssistantSession` against `MockOpenAIServer` on
/// 127.0.0.1. On Linux the transport buffers the whole SSE body (FoundationNetworking has no
/// byte streams); on macOS the same tests exercise the incremental Darwin path.
@MainActor
final class AssistantHTTPEndToEndTests: XCTestCase {
    var server: MockOpenAIServer!

    override func setUp() async throws {
        server = try MockOpenAIServer()
    }

    override func tearDown() async throws {
        server.stop()
        server = nil
    }

    func harness(model: String = "llama3.1:8b", apiKey: String? = "sk-local-test", tasks: [PlanTask] = []) async -> QAHarness {
        let (store, _) = await makeStore(tasks)
        return QAHarness(store: store, transport: OpenAIHTTPTransport(), settings: .qa(model: model, baseURL: server.baseURL), apiKey: apiKey)
    }

    static let openAIError404 = #"{"error":{"message":"The model `gpt-5-mini` does not exist or you do not have access to it.","type":"invalid_request_error","param":null,"code":"model_not_found"}}"#

    // MARK: Happy path

    func testListModelsOverHTTP() async throws {
        server.modelsResponse = .json(status: 200, body: #"""
        {"object":"list","data":[
          {"id":"gpt-6-luna","object":"model","created":1,"owned_by":"system","shutdown_date":null},
          {"id":"gpt-5-mini","object":"model","created":1,"owned_by":"system","shutdown_date":"2026-12-11"},
          {"id":"text-embedding-3-small","object":"model","created":1,"owned_by":"system"}]}
        """#)
        let endpoint = try AssistantEndpoint(baseURLString: server.baseURL + "/", apiKey: "sk-local-test")
        let transport = OpenAIHTTPTransport()
        let ids = try await transport.listModels(endpoint: endpoint)
        XCTAssertEqual(ids, ["gpt-5-mini", "gpt-6-luna", "text-embedding-3-small"])
        let infos = try await transport.listModelInfo(endpoint: endpoint)
        XCTAssertEqual(infos.first { $0.id == "gpt-5-mini" }?.shutdownDate, AssistantModelCapabilityTests.utcDay(2026, 12, 11))
        XCTAssertNil(infos.first { $0.id == "gpt-6-luna" }?.shutdownDate)
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/v1/models")
        XCTAssertEqual(request.headers["authorization"], "Bearer sk-local-test")
    }

    /// Text + two parallel tool calls whose arguments arrive split over several deltas, a usage
    /// chunk and [DONE]; then a second request carrying both tool results.
    func testFullTurnWithSplitToolCallDeltas() async throws {
        let list = #"{"start":"2026-11-07","end":"2026-11-08"}"#
        let create = #"{"tasks":[{"title":"Gym","start":"2026-11-07T18:00","duration_minutes":45,"category":"health"}]}"#
        server.enqueueChat(
            .sse(MockOpenAIServer.sse([
                SSEPayload.role(),
                SSEPayload.content("Let me "),
                SSEPayload.content("check."),
                SSEPayload.toolStart(index: 0, id: "call_abc", name: "list_tasks", args: String(list.prefix(10))),
                SSEPayload.toolArgs(index: 0, args: String(list.dropFirst(10).prefix(15))),
                SSEPayload.toolStart(index: 1, id: "call_def", name: "create_tasks", args: String(create.prefix(30))),
                SSEPayload.toolArgs(index: 0, args: String(list.dropFirst(25))),
                SSEPayload.toolArgs(index: 1, args: String(create.dropFirst(30))),
                SSEPayload.finish("tool_calls"),
                SSEPayload.usage(prompt: 1500, completion: 60, cached: 1024),
            ])),
            .sse(MockOpenAIServer.sse([SSEPayload.content("Gym is ready to review."), SSEPayload.finish("stop"), SSEPayload.usage(prompt: 1700, completion: 10, cached: 1500)]))
        )
        let h = await harness(tasks: [task("Standup", 10, minutes: 15, category: .meeting)])
        await h.send("add gym at 6")

        XCTAssertEqual(h.assistantTexts, ["Let me check.", "Gym is ready to review."])
        XCTAssertEqual(h.proposals.first?.items.map { $0.after?.title }, ["Gym"])
        XCTAssertEqual(h.session.usage, TokenUsage(promptTokens: 3200, completionTokens: 70, cachedTokens: 2524))
        XCTAssertTrue(h.errors.isEmpty, "\(h.errors)")

        let posts = server.chatRequests
        XCTAssertEqual(posts.count, 2)
        let first = try XCTUnwrap(posts[0].json)
        XCTAssertEqual(posts[0].headers["authorization"], "Bearer sk-local-test")
        XCTAssertEqual(posts[0].headers["content-type"], "application/json")
        XCTAssertEqual(first["model"], "llama3.1:8b")
        XCTAssertEqual(first["stream"], true)
        XCTAssertEqual(first["tools"]?.array?.compactMap { $0["function"]?["name"]?.string }, AssistantTool.allCases.map(\.rawValue))
        for key in ["reasoning_effort", "stream_options", "max_completion_tokens", "max_tokens", "temperature"] {
            XCTAssertNil(first[key], "\(key) must not be sent to a non-OpenAI host")
        }
        let messages = try XCTUnwrap(first["messages"]?.array)
        XCTAssertEqual(messages.map { $0["role"]?.string }, ["system", "user"], "local servers get one leading system message")
        XCTAssertEqual(messages[0]["content"]?.string?.hasPrefix(SystemPrompt.staticPart + "\n\nCONTEXT\n"), true)
        XCTAssertEqual(messages[1]["content"], "add gym at 6")

        let second = try XCTUnwrap(posts[1].json?["messages"]?.array)
        XCTAssertEqual(second.map { $0["role"]?.string }, ["system", "user", "assistant", "tool", "tool"])
        XCTAssertEqual(second[2]["content"], "Let me check.")
        let calls = try XCTUnwrap(second[2]["tool_calls"]?.array)
        XCTAssertEqual(calls.map { $0["id"]?.string }, ["call_abc", "call_def"])
        XCTAssertEqual(calls.map { $0["function"]?["arguments"]?.string }, [list, create], "deltas are reassembled exactly")
        XCTAssertEqual(calls.map { $0["type"]?.string }, ["function", "function"])
        XCTAssertEqual(second[3]["tool_call_id"], "call_abc")
        XCTAssertEqual(second[4]["tool_call_id"], "call_def")
        XCTAssertEqual(second[3]["content"]?.string.flatMap(JSONValue.parse)?["rows"], ["t1|2026-11-07T10:00|15|Standup|meeting|upcoming|"])
        XCTAssertEqual(second[4]["content"]?.string.flatMap(JSONValue.parse)?["status"], "proposed")
    }

    func testNoAPIKeyForALocalServerSendsNoAuthorizationHeader() async throws {
        server.enqueueChat(.sse(MockOpenAIServer.sse([SSEPayload.content("Hi"), SSEPayload.finish("stop")]), chunked: false))
        let h = await harness(apiKey: nil)
        await h.send("hello")
        XCTAssertEqual(h.assistantTexts, ["Hi"])
        XCTAssertNil(server.chatRequests.first?.headers["authorization"])
    }

    func testCRLFLineEndingsCommentsAndEventLines() async throws {
        let body = MockOpenAIServer.sse(
            [SSEPayload.role(), SSEPayload.content("Line endings "), SSEPayload.content("are fine."), SSEPayload.finish("stop")],
            lineEnding: "\r\n", extraLines: [": keep-alive", "event: message", "id: 1", "retry: 1000"]
        )
        server.enqueueChat(.sse(body))
        let h = await harness()
        await h.send("hello")
        XCTAssertEqual(h.assistantTexts, ["Line endings are fine."])
        XCTAssertTrue(h.errors.isEmpty, "\(h.errors)")
    }

    // MARK: Errors

    func testUnauthorized() async throws {
        server.enqueueChat(.json(status: 401, body: #"{"error":{"message":"Incorrect API key provided: sk-loca***test.","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}"#))
        let h = await harness()
        await h.send("hello")
        XCTAssertEqual(h.errors.map(\.0), [AssistantError.unauthorized("").userMessage])
        XCTAssertEqual(h.errors.first?.1, false)
        XCTAssertEqual(server.chatRequests.count, 1)
    }

    func testModelNotFoundFallsBackViaModelsList() async throws {
        server.modelsResponse = .json(status: 200, body: #"""
        {"object":"list","data":[
          {"id":"dall-e-3"},{"id":"gpt-4o-mini-tts"},{"id":"gpt-5-mini","shutdown_date":"2026-12-11"},
          {"id":"gpt-5.4-mini"},{"id":"gpt-6-astra"},{"id":"gpt-6-luna"},{"id":"gpt-realtime-mini"},
          {"id":"text-embedding-3-large"},{"id":"whisper-1"}]}
        """#)
        server.enqueueChat(
            .json(status: 404, body: Self.openAIError404),
            .sse(MockOpenAIServer.sse([SSEPayload.content("Hello from the fallback."), SSEPayload.finish("stop")]))
        )
        let h = await harness(model: "gpt-5-mini")
        await h.send("hello")
        XCTAssertEqual(h.fallbacks, ["gpt-6-luna"])
        XCTAssertEqual(h.notices, ["“gpt-5-mini” isn't available, so I switched to gpt-6-luna."])
        XCTAssertEqual(h.assistantTexts, ["Hello from the fallback."])
        XCTAssertEqual(server.requests.map { "\($0.method) \($0.path)" }, ["POST /v1/chat/completions", "GET /v1/models", "POST /v1/chat/completions"])
        XCTAssertEqual(server.chatRequests.last?.json?["model"], "gpt-6-luna")
    }

    func testOllamaStyleModelNotFoundSkipsEmbeddingModels() async throws {
        server.modelsResponse = .json(status: 200, body: #"{"object":"list","data":[{"id":"all-minilm:latest","object":"model","created":1,"owned_by":"library"},{"id":"nomic-embed-text:latest","object":"model","created":1,"owned_by":"library"},{"id":"qwen2.5:7b","object":"model","created":1,"owned_by":"library"}]}"#)
        server.enqueueChat(
            .json(status: 404, body: #"{"error":{"message":"model \"gpt-6-luna\" not found, try pulling it first","type":"api_error","param":null,"code":null}}"#),
            .sse(MockOpenAIServer.sse([SSEPayload.content("Hi"), SSEPayload.finish("stop")]))
        )
        let h = await harness(model: "gpt-6-luna", apiKey: nil)
        await h.send("hello")
        XCTAssertEqual(h.fallbacks, ["qwen2.5:7b"])
        XCTAssertEqual(server.chatRequests.last?.json?["model"], "qwen2.5:7b")
    }

    func testWrongBasePathIsExplained() async throws {
        let (store, _) = await makeStore([])
        let base = "http://127.0.0.1:\(server.port)"  // missing /v1
        let h = QAHarness(store: store, transport: OpenAIHTTPTransport(), settings: .qa(model: "llama3.1:8b", baseURL: base))
        await h.send("hello")
        XCTAssertEqual(h.errors.count, 1)
        XCTAssertTrue(h.errors.first?.0.contains("check the server address") == true, h.errors.first?.0 ?? "")
    }

    func testRateLimitWithRetryAfterIsRetried() async throws {
        server.enqueueChat(
            .json(status: 429, body: #"{"error":{"message":"Rate limit reached for requests","type":"requests","param":null,"code":"rate_limit_exceeded"}}"#, headers: ["Retry-After": "1"]),
            .sse(MockOpenAIServer.sse([SSEPayload.content("After the wait."), SSEPayload.finish("stop")]))
        )
        let h = await harness()
        let start = Date()
        await h.send("hello")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.95)
        XCTAssertEqual(h.assistantTexts, ["After the wait."])
        XCTAssertEqual(server.chatRequests.count, 2)
    }

    func testQuotaExceededIsNotRetried() async throws {
        server.enqueueChat(.json(status: 429, body: #"{"error":{"message":"You exceeded your current quota, please check your plan and billing details.","type":"insufficient_quota","param":null,"code":"insufficient_quota"}}"#))
        let h = await harness()
        await h.send("hello")
        XCTAssertEqual(h.errors.map(\.0), [AssistantError.quotaExceeded("").userMessage])
        XCTAssertEqual(h.errors.first?.1, false)
        XCTAssertEqual(server.chatRequests.count, 1)
    }

    func testServerErrorIsRetriedOnceThenSurfaced() async throws {
        let error500 = MockOpenAIServer.Response.json(status: 500, body: #"{"error":{"message":"The server had an error while processing your request.","type":"server_error"}}"#)
        server.enqueueChat(error500, .sse(MockOpenAIServer.sse([SSEPayload.content("Recovered."), SSEPayload.finish("stop")])))
        let h = await harness()
        await h.send("hello")
        XCTAssertEqual(h.assistantTexts, ["Recovered."])

        server.enqueueChat(error500, error500)
        await h.send("again")
        XCTAssertEqual(h.errors.map(\.0), ["Server error 500. The server had an error while processing your request."])
        XCTAssertEqual(h.errors.first?.1, true)
        XCTAssertEqual(server.chatRequests.count, 4)
    }

    func testErrorEventMidStreamIsSurfaced() async throws {
        server.enqueueChat(.sse(MockOpenAIServer.sse([
            SSEPayload.content("Working on"),
            #"{"error":{"message":"The model produced invalid content.","type":"server_error","code":null}}"#,
        ], done: false)))
        let h = await harness()
        await h.send("hello")
        XCTAssertEqual(h.errors.map(\.0), ["Server error 200. The model produced invalid content."])
        XCTAssertTrue(h.assistantTexts.isEmpty, "a broken reply isn't committed as if it were complete")
    }

    func testEmptyStreamIsSurfaced() async throws {
        server.enqueueChat(.sse(MockOpenAIServer.sse([SSEPayload.role(), SSEPayload.finish("stop")])))
        let h = await harness()
        await h.send("hello")
        XCTAssertEqual(h.errors.count, 1)
        XCTAssertEqual(h.errors.first?.1, true)
    }
}
