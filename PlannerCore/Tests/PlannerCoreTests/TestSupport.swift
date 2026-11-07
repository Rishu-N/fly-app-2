import Foundation
@testable import PlannerCore

enum TestClock {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }()

    /// 2026-11-07 (a Saturday) at hh:mm local.
    static func at(_ hour: Int, _ minute: Int = 0, day: Int = 7, month: Int = 11, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
}

func task(_ title: String, _ h: Int, _ m: Int = 0, minutes: Int = 60, day: Int = 7, month: Int = 11, status: TaskStatus = .planned, category: TaskCategory = .focus) -> PlanTask {
    PlanTask(title: title, start: TestClock.at(h, m, day: day, month: month), durationMinutes: minutes, category: category, status: status, createdAt: TestClock.at(6))
}

@MainActor
func makeStore(_ tasks: [PlanTask] = [], now: Date = TestClock.at(9)) async -> (TaskStore, InMemoryPersistence) {
    let persistence = InMemoryPersistence(tasks: tasks, calendar: TestClock.calendar)
    let store = TaskStore(persistence: persistence, calendar: TestClock.calendar)
    store.flushDelay = .milliseconds(1)
    await store.bootstrap(now: now)
    return (store, persistence)
}

/// Scripted fake model: each call to `stream` pops the next scripted reply.
final class ScriptedTransport: ChatTransport, @unchecked Sendable {
    enum Reply {
        case text(String)
        case tools([(name: String, args: String)], text: String = "")
        case failure(AssistantError)
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [ChatRequest] = []
    var models: [String] = ["gpt-4.1-mini", "gpt-6-luna", "text-embedding-3-small"]

    init(_ replies: [Reply]) { self.replies = replies }

    func listModels(endpoint: AssistantEndpoint) async throws -> [String] { models }

    func stream(_ request: ChatRequest, endpoint: AssistantEndpoint) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        lock.lock()
        requests.append(request)
        let reply = replies.isEmpty ? Reply.text("(no more script)") : replies.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { continuation in
            switch reply {
            case .failure(let e):
                continuation.finish(throwing: e)
            case .text(let text):
                for piece in text.split(separator: " ", omittingEmptySubsequences: false) {
                    continuation.yield(Self.chunk(#"{"choices":[{"index":0,"delta":{"content":"\#(piece) "}}]}"#))
                }
                continuation.yield(Self.chunk(#"{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":20}}"#))
                continuation.finish()
            case .tools(let calls, let text):
                if !text.isEmpty {
                    continuation.yield(Self.chunk(#"{"choices":[{"index":0,"delta":{"content":\#(Self.quote(text))}}]}"#))
                }
                for (i, call) in calls.enumerated() {
                    // Split arguments in two deltas to exercise accumulation.
                    let mid = call.args.index(call.args.startIndex, offsetBy: call.args.count / 2)
                    let a = String(call.args[..<mid]), b = String(call.args[mid...])
                    continuation.yield(Self.chunk(#"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":\#(i),"id":"call_\#(i)","type":"function","function":{"name":"\#(call.name)","arguments":\#(Self.quote(a))}}]}}]}"#))
                    continuation.yield(Self.chunk(#"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":\#(i),"function":{"arguments":\#(Self.quote(b))}}]}}]}"#))
                }
                continuation.yield(Self.chunk(#"{"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#))
                continuation.finish()
            }
        }
    }

    static func chunk(_ json: String) -> ChatStreamChunk {
        try! JSONDecoder().decode(ChatStreamChunk.self, from: Data(json.utf8))
    }

    static func quote(_ s: String) -> String {
        String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
    }
}
