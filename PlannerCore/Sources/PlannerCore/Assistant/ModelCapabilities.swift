import Foundation

/// What a model id supports on Chat Completions with function calling.
///
/// OpenAI rows were verified against developers.openai.com on 2026-11-09
/// (docs/research/verification-2026-11.md §A). Unknown and third-party ids (Ollama, LM Studio…)
/// get conservative defaults: tools allowed, no `reasoning_effort`, `system` role.
public struct ModelCapabilities: Hashable, Sendable {
    /// Tool calling works through Chat Completions. When false the assistant can't use the model.
    public var supportsChatTools: Bool
    /// `reasoning_effort` values the model accepts, lowest first. Empty: never send the parameter.
    public var allowedEfforts: [String]
    /// When set, this effort is always sent (GPT-6 Luna/Sol only call tools at `"none"`).
    public var forcedEffort: String?
    /// Instructions go in a `developer` message instead of `system` (o1 and newer).
    public var usesDeveloperRole: Bool

    public init(supportsChatTools: Bool = true, allowedEfforts: [String] = [], forcedEffort: String? = nil, usesDeveloperRole: Bool = false) {
        self.supportsChatTools = supportsChatTools
        self.allowedEfforts = allowedEfforts
        self.forcedEffort = forcedEffort
        self.usesDeveloperRole = usesDeveloperRole
    }

    /// True when the effort picker should be shown (the model takes an effort and none is forced).
    public var hasEffortChoice: Bool { forcedEffort == nil && allowedEfforts.count > 1 }

    /// The effort to send for the user's choice: the forced one, else the choice if the model
    /// accepts it, else nil (omit the parameter).
    public func effort(forRequested requested: String) -> String? {
        if let forcedEffort { return forcedEffort }
        let choice = requested.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allowedEfforts.contains(choice) ? choice : nil
    }

    static let noneToMax = ["none", "low", "medium", "high", "xhigh", "max"]
    static let lowToMax = ["low", "medium", "high", "xhigh", "max"]
    static let noneToXHigh = ["none", "low", "medium", "high", "xhigh"]

    /// Substrings of ids that are not chat models with tools (embeddings, speech, images,
    /// search/computer-use/deep-research variants, legacy completions models…).
    static let nonChatMarkers = [
        "embed", "minilm", "rerank", "bge-", "whisper", "tts", "dall-e", "image", "audio", "realtime", "transcribe",
        "moderation", "search", "codex", "sora", "computer-use", "deep-research", "gpt-3.5-turbo-instruct",
        "babbage", "davinci", "chatgpt-",
    ]

    public static func `for`(_ model: String) -> ModelCapabilities {
        var id = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let slash = id.lastIndex(of: "/") { id = String(id[id.index(after: slash)...]) }  // "openai/gpt-6-luna"

        if nonChatMarkers.contains(where: id.contains) { return ModelCapabilities(supportsChatTools: false) }

        /// `name` itself or a dated/suffixed snapshot of it ("gpt-5.4-mini-2026-03-17").
        func family(_ name: String) -> Bool { id == name || id.hasPrefix(name + "-") }

        // GPT-6: Luna/Sol call tools on Chat Completions only at effort "none"; Astra and 6.1
        // need the Responses API for tools.
        if family("gpt-6-luna") || family("gpt-6-sol") {
            return ModelCapabilities(allowedEfforts: noneToMax, forcedEffort: "none", usesDeveloperRole: true)
        }
        if family("gpt-6-astra") || family("gpt-6.1-sol") {
            return ModelCapabilities(supportsChatTools: false, allowedEfforts: lowToMax, usesDeveloperRole: true)
        }
        if family("gpt-6.1-terra") {
            return ModelCapabilities(supportsChatTools: false, allowedEfforts: noneToMax, usesDeveloperRole: true)
        }
        if id.hasPrefix("gpt-6") {
            // A GPT-6 id not in the verified table: assume tools need "none" like Luna/Sol.
            return ModelCapabilities(allowedEfforts: noneToMax, forcedEffort: "none", usesDeveloperRole: true)
        }
        if family("gpt-5.6-luna") || family("gpt-5.6-terra") || family("gpt-5.6-sol") {
            return ModelCapabilities(allowedEfforts: noneToMax, usesDeveloperRole: true)
        }
        if family("gpt-5.4-mini") || family("gpt-5.4-nano") {
            return ModelCapabilities(allowedEfforts: noneToXHigh, usesDeveloperRole: true)
        }
        if id.hasPrefix("gpt-5") {
            // Other GPT-5.x ids (training knowledge, not re-verified). Chat-tuned variants take no effort.
            if id.contains("-chat") { return ModelCapabilities(usesDeveloperRole: true) }
            if family("gpt-5") || family("gpt-5-mini") || family("gpt-5-nano") {
                return ModelCapabilities(allowedEfforts: ["minimal", "low", "medium", "high"], usesDeveloperRole: true)
            }
            if id.hasPrefix("gpt-5.1") { return ModelCapabilities(allowedEfforts: ["none", "low", "medium", "high"], usesDeveloperRole: true) }
            return ModelCapabilities(allowedEfforts: noneToXHigh, usesDeveloperRole: true)
        }
        if let first = id.first, first == "o", id.dropFirst().first?.isNumber == true {
            return ModelCapabilities(allowedEfforts: ["low", "medium", "high"], usesDeveloperRole: true)
        }
        // gpt-4.x, gpt-4o, gpt-3.5 and every third-party id.
        return ModelCapabilities()
    }
}

/// One entry of `GET /models`. `shutdownDate` is decoded leniently (YYYY-MM-DD, ISO 8601 or
/// unix seconds/milliseconds); anything unreadable is treated as "no date".
public struct ModelInfo: Hashable, Sendable, Decodable {
    public var id: String
    public var shutdownDate: Date?

    public init(id: String, shutdownDate: Date? = nil) {
        self.id = id
        self.shutdownDate = shutdownDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case shutdownDate = "shutdown_date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        if let seconds = try? c.decodeIfPresent(Double.self, forKey: .shutdownDate) {
            shutdownDate = Self.date(fromNumber: seconds)
        } else if let text = try? c.decodeIfPresent(String.self, forKey: .shutdownDate) {
            shutdownDate = Self.date(fromString: text)
        } else {
            shutdownDate = nil
        }
    }

    static func date(fromNumber n: Double) -> Date? {
        guard n.isFinite, n > 0 else { return nil }
        return Date(timeIntervalSince1970: n > 100_000_000_000 ? n / 1000 : n)
    }

    static func date(fromString raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let n = Double(s) { return date(fromNumber: n) }
        let parts = s.prefix(10).split(separator: "-").compactMap { Int($0) }
        if s.count == 10, parts.count == 3 {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }
}
