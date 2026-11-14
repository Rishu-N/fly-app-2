import XCTest
@testable import PlannerCore

/// Model capabilities, defaults/migration and what each model gets on the wire
/// (docs/research/verification-2026-11.md §A, verified 2026-11-09).
@MainActor
final class AssistantModelCapabilityTests: XCTestCase {
    static let noneToMax = ["none", "low", "medium", "high", "xhigh", "max"]

    // MARK: Table

    func testVerifiedOpenAIRows() async {
        for id in ["gpt-6-luna", "gpt-6-sol", "GPT-6-Luna", " gpt-6-luna ", "openai/gpt-6-luna"] {
            let c = ModelCapabilities.for(id)
            XCTAssertTrue(c.supportsChatTools, id)
            XCTAssertEqual(c.forcedEffort, "none", id)
            XCTAssertEqual(c.allowedEfforts, Self.noneToMax, id)
            XCTAssertTrue(c.usesDeveloperRole, id)
            XCTAssertEqual(c.effort(forRequested: "high"), "none", "tools on Chat Completions need effort none")
            XCTAssertFalse(c.hasEffortChoice)
        }
        for id in ["gpt-6-astra", "gpt-6.1-sol"] {
            let c = ModelCapabilities.for(id)
            XCTAssertFalse(c.supportsChatTools, id)
            XCTAssertFalse(c.allowedEfforts.contains("none"), id)
        }
        XCTAssertFalse(ModelCapabilities.for("gpt-6.1-terra").supportsChatTools)
        XCTAssertEqual(ModelCapabilities.for("gpt-6.1-terra").allowedEfforts, Self.noneToMax)

        for id in ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"] {
            let c = ModelCapabilities.for(id)
            XCTAssertTrue(c.supportsChatTools, id)
            XCTAssertNil(c.forcedEffort, id)
            XCTAssertEqual(c.allowedEfforts, Self.noneToMax, id)
            XCTAssertTrue(c.hasEffortChoice)
            XCTAssertEqual(c.effort(forRequested: "Medium"), "medium")
            XCTAssertNil(c.effort(forRequested: "minimal"), "no current small model supports minimal")
        }
        for id in ["gpt-5.4-mini", "gpt-5.4-mini-2026-03-17"] {
            let c = ModelCapabilities.for(id)
            XCTAssertEqual(c.allowedEfforts, ["none", "low", "medium", "high", "xhigh"], id)
            XCTAssertNil(c.effort(forRequested: "max"))
            XCTAssertTrue(c.usesDeveloperRole)
        }
        XCTAssertEqual(ModelCapabilities.for("gpt-5-mini").allowedEfforts, ["minimal", "low", "medium", "high"])
    }

    func testUnknownAndOlderModelsGetConservativeDefaults() async {
        for id in ["gpt-4.1-mini", "gpt-4o", "gpt-3.5-turbo", "llama3.1:8b", "qwen2.5:7b", "llama-3.1-8b-instruct", "mistral-7b-instruct-v0.3", "my-local-model"] {
            let c = ModelCapabilities.for(id)
            XCTAssertEqual(c, ModelCapabilities(), id)
            XCTAssertNil(c.effort(forRequested: "low"), id)
        }
    }

    func testNonChatModelsCantUseTools() async {
        for id in ["text-embedding-3-small", "nomic-embed-text:latest", "all-minilm", "whisper-1", "tts-1-hd", "gpt-4o-mini-tts", "dall-e-3",
                   "gpt-image-1", "gpt-4o-mini-transcribe", "gpt-realtime-mini", "gpt-audio-mini", "gpt-4o-mini-search-preview",
                   "omni-moderation-latest", "codex-mini-latest", "gpt-5-codex", "sora-2", "computer-use-preview",
                   "o4-mini-deep-research", "gpt-3.5-turbo-instruct", "babbage-002", "davinci-002", "chatgpt-4o-latest"] {
            XCTAssertFalse(ModelCapabilities.for(id).supportsChatTools, id)
        }
    }

    // MARK: Settings

    func testDefaultsAndPresets() async {
        let s = AssistantSettings()
        XCTAssertEqual(s.model, "gpt-6-luna")
        XCTAssertEqual(s.reasoningEffort, "none")
        XCTAssertEqual(AssistantSettings.modelPresets, ["gpt-6-luna", "gpt-5.6-luna", "gpt-5.4-mini", "gpt-6-sol", "gpt-5.6-terra"])
        for preset in AssistantSettings.modelPresets {
            XCTAssertTrue(ModelCapabilities.for(preset).supportsChatTools, "\(preset) must work with tools")
        }
    }

    func testStoredSettingsMigrate() async throws {
        func decode(_ json: String) throws -> AssistantSettings {
            try JSONDecoder().decode(PlannerSettings.self, from: Data(#"{"defaultLeadMinutes":10,"assistant":\#(json)}"#.utf8)).assistant
        }
        for retired in ["gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-4.1-mini", "gpt-4o-mini", "gpt-4.1-nano", "o4-mini", "o3-mini"] {
            XCTAssertEqual(try decode(#"{"model":"\#(retired)"}"#).model, "gpt-6-luna", retired)
        }
        let old = try decode(#"{"model":"gpt-5-mini","reasoningEffort":"minimal","shareNotes":true,"baseURL":"https://api.openai.com/v1"}"#)
        XCTAssertEqual(old.model, "gpt-6-luna")
        XCTAssertEqual(old.reasoningEffort, "low")
        XCTAssertTrue(old.shareNotes, "other fields survive the migration")
        let kept = try decode(#"{"model":"gpt-5.4-mini","reasoningEffort":"high"}"#)
        XCTAssertEqual(kept.model, "gpt-5.4-mini")
        XCTAssertEqual(kept.reasoningEffort, "high")
        XCTAssertEqual(try decode(#"{"model":"llama3.1:8b","baseURL":"http://192.168.1.5:11434/v1"}"#).model, "llama3.1:8b")
        XCTAssertEqual(try decode("{}").model, "gpt-6-luna")
    }

    // MARK: Wire

    func requestJSON(model: String, effort: String, baseURL: String = "https://api.openai.com/v1") async throws -> JSONValue {
        let (store, _) = await makeStore([task("Standup", 10, minutes: 15, category: .meeting)])
        var settings = PlannerSettings.qa(model: model, baseURL: baseURL)
        settings.assistant.reasoningEffort = effort
        let h = QAHarness(store: store, transport: QAModel([.reply("ok"), .reply("ok")]), settings: settings)
        await h.send("first")
        await h.send("second")
        return try XCTUnwrap(JSONValue.parse(h.requestJSON(1)))
    }

    func roles(_ json: JSONValue) -> [String] {
        (json["messages"]?.array ?? []).compactMap { $0["role"]?.string }
    }

    func testGPT6LunaSendsDeveloperRoleAndEffortNone() async throws {
        let json = try await requestJSON(model: "gpt-6-luna", effort: "high")
        XCTAssertEqual(roles(json), ["developer", "user", "assistant", "developer", "user"])
        XCTAssertEqual(json["messages"]?.array?.first?["content"]?.string, SystemPrompt.staticPart)
        XCTAssertEqual(json["messages"]?.array?[3]["content"]?.string?.hasPrefix("CONTEXT\n"), true)
        XCTAssertEqual(json["reasoning_effort"], "none")
        XCTAssertEqual(json["max_completion_tokens"], 3000)
        XCTAssertNil(json["max_tokens"], "max_tokens is deprecated")
        XCTAssertEqual(json["stream_options"], ["include_usage": true])
        XCTAssertNil(json["temperature"])
        XCTAssertEqual(json["tools"]?.array?.count, AssistantTool.allCases.count)
    }

    func testGPT56PassesTheUsersEffortOnlyWhenAllowed() async throws {
        let medium = try await requestJSON(model: "gpt-5.6-luna", effort: "medium")
        XCTAssertEqual(medium["reasoning_effort"], "medium")
        let minimal = try await requestJSON(model: "gpt-5.6-luna", effort: "minimal")
        XCTAssertNil(minimal["reasoning_effort"])
        let max = try await requestJSON(model: "gpt-5.4-mini", effort: "max")
        XCTAssertNil(max["reasoning_effort"])
    }

    func testOlderAndLocalModelsKeepSystemRoleAndNoEffort() async throws {
        let mini = try await requestJSON(model: "gpt-4.1-mini", effort: "low")
        XCTAssertEqual(roles(mini), ["system", "user", "assistant", "system", "user"])
        XCTAssertNil(mini["reasoning_effort"])
        // A local server gets one leading system message and none of the OpenAI-only parameters,
        // even for an OpenAI model id.
        let local = try await requestJSON(model: "gpt-6-luna", effort: "high", baseURL: "http://192.168.1.20:11434/v1")
        XCTAssertEqual(roles(local), ["system", "user", "assistant", "user"])
        XCTAssertEqual(local["messages"]?.array?.first?["content"]?.string?.hasPrefix(SystemPrompt.staticPart + "\n\nCONTEXT\n"), true)
        for key in ["reasoning_effort", "stream_options", "max_completion_tokens"] { XCTAssertNil(local[key], key) }
        XCTAssertEqual(local["stream"], true)
    }

    func testOpenAIHostDetectionIsExact() async throws {
        XCTAssertTrue(try AssistantEndpoint(baseURLString: "https://api.openai.com/v1", apiKey: "k").isOpenAI)
        XCTAssertTrue(try AssistantEndpoint(baseURLString: "https://API.OpenAI.com/v1/", apiKey: "k").isOpenAI)
        XCTAssertFalse(try AssistantEndpoint(baseURLString: "https://notopenai.com/v1", apiKey: "k").isOpenAI)
        XCTAssertFalse(try AssistantEndpoint(baseURLString: "http://127.0.0.1:8080/v1", apiKey: "").isOpenAI)
    }

    func testAModelWithoutChatToolsFailsTheTurnWithoutSending() async throws {
        let (store, _) = await makeStore([])
        let model = QAModel([.reply("never")])
        let h = QAHarness(store: store, transport: model, settings: .qa(model: "gpt-6-astra"))
        await h.send("plan my day")
        XCTAssertTrue(model.requests.isEmpty)
        XCTAssertEqual(h.errors.count, 1)
        XCTAssertEqual(h.errors.first?.1, false)
        XCTAssertTrue(h.errors.first?.0.contains("tool-capable") == true, h.errors.first?.0 ?? "")
    }

    // MARK: reasoning_effort retry

    func testEffortErrorRetriesOnceWithNoneInsteadOfDropping() async throws {
        let (store, _) = await makeStore([])
        let model = QAModel([
            .fail(.server(status: 400, message: "Function calling is not supported with reasoning_effort 'medium' on this model.")),
            .reply("ok"),
            .reply("still ok"),
        ])
        var settings = PlannerSettings.qa(model: "gpt-5.6-luna")
        settings.assistant.reasoningEffort = "medium"
        let h = QAHarness(store: store, transport: model, settings: settings)
        await h.send("hi")
        XCTAssertEqual(h.requests.map(\.reasoningEffort), ["medium", "none"])
        await h.send("again")
        XCTAssertEqual(h.requests.last?.reasoningEffort, "none", "the override sticks for this model")
        XCTAssertTrue(h.errors.isEmpty)
    }

    func testEffortErrorWhenNoneWasAlreadySentIsShownNotDropped() async throws {
        let (store, _) = await makeStore([])
        let model = QAModel([.fail(.server(status: 400, message: "Unsupported value: 'reasoning_effort' does not support 'none' with this model.")), .reply("never")])
        let h = QAHarness(store: store, transport: model, settings: .qa(model: "gpt-6-luna"))
        await h.send("hi")
        XCTAssertEqual(h.requests.count, 1, "dropping it would mean the API default (medium), which can't call tools")
        XCTAssertEqual(h.errors.count, 1)
    }

    // MARK: Fallback with shutdown dates

    static func utcDay(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testFallbackSkipsModelsShutDownOrShuttingDownWithin30Days() async {
        let models = [
            ModelInfo(id: "gpt-5-mini", shutdownDate: Self.utcDay(2026, 12, 11)),
            ModelInfo(id: "gpt-5-nano", shutdownDate: Self.utcDay(2026, 12, 11)),
            ModelInfo(id: "gpt-4.1-nano", shutdownDate: Self.utcDay(2026, 10, 23)),
            ModelInfo(id: "gpt-4.1-mini", shutdownDate: Self.utcDay(2027, 1, 14)),
            ModelInfo(id: "gpt-5.6-terra"),
            ModelInfo(id: "gpt-6-astra"),
            ModelInfo(id: "text-embedding-3-small"),
        ]
        XCTAssertEqual(AssistantSession.chooseFallback(from: models, unavailable: "gpt-6-luna", now: Self.utcDay(2026, 11, 14)), "gpt-4.1-mini")
        XCTAssertEqual(AssistantSession.chooseFallback(from: models, unavailable: "gpt-6-luna", now: Self.utcDay(2026, 12, 20)), "gpt-5.6-terra")
        XCTAssertNil(AssistantSession.chooseFallback(from: Array(models.prefix(3)), unavailable: "gpt-6-luna", now: Self.utcDay(2026, 11, 14)))
        let current = [ModelInfo(id: "gpt-5.4-mini"), ModelInfo(id: "gpt-5.6-luna"), ModelInfo(id: "gpt-6-luna"), ModelInfo(id: "gpt-6-sol"), ModelInfo(id: "gpt-5.2-pro")]
        XCTAssertEqual(AssistantSession.chooseFallback(from: current, unavailable: "gpt-5-mini", now: Self.utcDay(2026, 11, 14)), "gpt-6-luna")
        XCTAssertEqual(AssistantSession.chooseFallback(from: [ModelInfo(id: "gpt-5.2-pro"), ModelInfo(id: "gpt-6-sol")], unavailable: "x", now: Self.utcDay(2026, 11, 14)), "gpt-6-sol", "premium -pro ids are never auto-picked")
    }

    func testSessionFallbackUsesShutdownDates() async throws {
        let (store, _) = await makeStore([])
        let model = QAModel([.fail(.modelNotFound("gpt-6-luna")), .reply("Hello")])
        model.modelInfos = [
            ModelInfo(id: "gpt-5.4-mini", shutdownDate: TestClock.at(9, day: 20)),  // 13 days after "now"
            ModelInfo(id: "gpt-5.6-terra"),
            ModelInfo(id: "whisper-1"),
        ]
        let h = QAHarness(store: store, transport: model)
        await h.send("hi")
        XCTAssertEqual(h.fallbacks, ["gpt-5.6-terra"])
        XCTAssertEqual(h.requests.map(\.model), ["gpt-6-luna", "gpt-5.6-terra"])
    }

    func testModelListDecodesShutdownDatesLeniently() async throws {
        let dec11 = Self.utcDay(2026, 12, 11)
        let seconds = Int(dec11.timeIntervalSince1970)
        let json = #"""
        {"object":"list","data":[
          {"id":"a","object":"model","created":1,"owned_by":"system","shutdown_date":"2026-12-11"},
          {"id":"b","shutdown_date":null},
          {"id":"c","shutdown_date":\#(seconds)},
          {"id":"d","shutdown_date":"2026-12-11T00:00:00Z"},
          {"id":"e","shutdown_date":"soon"},
          {"id":"f"},
          {"id":"g","shutdown_date":\#(seconds)000},
          {"id":"h","shutdown_date":{"weird":true}},
          {"id":"i","shutdown_date":"2026-12-11T00:00:00.000Z"}
        ]}
        """#
        let list = try JSONDecoder().decode(ModelList.self, from: Data(json.utf8))
        let dates = Dictionary(uniqueKeysWithValues: list.data.map { ($0.id, $0.shutdownDate) })
        XCTAssertEqual(dates["a"] ?? nil, dec11)
        XCTAssertNil(dates["b"] ?? nil)
        XCTAssertEqual(dates["c"] ?? nil, dec11)
        XCTAssertEqual(dates["d"] ?? nil, dec11)
        XCTAssertNil(dates["e"] ?? nil)
        XCTAssertNil(dates["f"] ?? nil)
        XCTAssertEqual(dates["g"] ?? nil, dec11, "milliseconds are recognised")
        XCTAssertNil(dates["h"] ?? nil)
        XCTAssertEqual(dates["i"] ?? nil, dec11)
    }

    // MARK: Usage

    func testUsageDecodesCacheWriteTokensAndAccumulates() async throws {
        let usage = try JSONDecoder().decode(TokenUsage.self, from: Data(#"{"prompt_tokens":2000,"completion_tokens":40,"prompt_tokens_details":{"cached_tokens":1024,"cache_write_tokens":900}}"#.utf8))
        XCTAssertEqual(usage, TokenUsage(promptTokens: 2000, completionTokens: 40, cachedTokens: 1024, cacheWriteTokens: 900))
        let roundTrip = try JSONDecoder().decode(TokenUsage.self, from: JSONEncoder().encode(usage))
        XCTAssertEqual(roundTrip, usage)
        XCTAssertNil((TokenUsage() + TokenUsage(promptTokens: 1)).cacheWriteTokens)
        XCTAssertEqual((usage + usage).cacheWriteTokens, 1800)

        let (store, _) = await makeStore([])
        let chunk = #"{"choices":[],"usage":{"prompt_tokens":2000,"completion_tokens":40,"prompt_tokens_details":{"cached_tokens":1024,"cache_write_tokens":900}}}"#
        let h = QAHarness(store: store, transport: QAModel([.chunks([SSEPayload.content("Hi"), SSEPayload.finish("stop"), chunk])]))
        await h.send("hi")
        XCTAssertEqual(h.session.usage, TokenUsage(promptTokens: 2000, completionTokens: 40, cachedTokens: 1024, cacheWriteTokens: 900))
    }
}
