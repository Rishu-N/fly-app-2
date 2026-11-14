import Foundation

/// User preferences. Small, Codable and stored in the shared App Group defaults so the widget
/// extension can read it too. The OpenAI API key is *never* stored here — it lives in the Keychain.
public struct PlannerSettings: Codable, Hashable, Sendable {
    // Reminders
    public var defaultLeadMinutes: Int = 5
    public var timeSensitiveReminders: Bool = true
    public var notifyWhenTimerEnds: Bool = true
    public var remindersEnabled: Bool = true

    // Planning defaults
    public var defaultDurationMinutes: Int = 30
    public var dayStartHour: Int = 7
    public var dayEndHour: Int = 22
    /// When the timer reaches zero the task keeps counting up (overrun) until the user acts.
    /// If true, it is completed automatically instead.
    public var autoCompleteWhenTimerEnds: Bool = false

    // Feel
    public var hapticsEnabled: Bool = true
    public var liveActivitiesEnabled: Bool = true
    public var ambientBackground: Bool = true

    // Assistant
    public var assistant = AssistantSettings()

    public init() {}

    public static let leadTimeChoices = [0, 1, 2, 5, 10, 15, 30, 60]

    public init(from decoder: Decoder) throws {
        // Tolerant: every field falls back to its default.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlannerSettings()
        defaultLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultLeadMinutes) ?? d.defaultLeadMinutes
        timeSensitiveReminders = try c.decodeIfPresent(Bool.self, forKey: .timeSensitiveReminders) ?? d.timeSensitiveReminders
        notifyWhenTimerEnds = try c.decodeIfPresent(Bool.self, forKey: .notifyWhenTimerEnds) ?? d.notifyWhenTimerEnds
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? d.remindersEnabled
        defaultDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultDurationMinutes) ?? d.defaultDurationMinutes
        dayStartHour = try c.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? d.dayStartHour
        dayEndHour = try c.decodeIfPresent(Int.self, forKey: .dayEndHour) ?? d.dayEndHour
        autoCompleteWhenTimerEnds = try c.decodeIfPresent(Bool.self, forKey: .autoCompleteWhenTimerEnds) ?? d.autoCompleteWhenTimerEnds
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? d.hapticsEnabled
        liveActivitiesEnabled = try c.decodeIfPresent(Bool.self, forKey: .liveActivitiesEnabled) ?? d.liveActivitiesEnabled
        ambientBackground = try c.decodeIfPresent(Bool.self, forKey: .ambientBackground) ?? d.ambientBackground
        assistant = try c.decodeIfPresent(AssistantSettings.self, forKey: .assistant) ?? d.assistant
    }

    private enum CodingKeys: String, CodingKey {
        case defaultLeadMinutes, timeSensitiveReminders, notifyWhenTimerEnds, remindersEnabled
        case defaultDurationMinutes, dayStartHour, dayEndHour, autoCompleteWhenTimerEnds
        case hapticsEnabled, liveActivitiesEnabled, ambientBackground, assistant
    }
}

public struct AssistantSettings: Codable, Hashable, Sendable {
    /// Any OpenAI chat model id. Editable free text in Settings, with presets.
    public var model: String = AssistantSettings.defaultModel
    /// OpenAI by default; any OpenAI-compatible server (e.g. a local Ollama / LM Studio on your
    /// network) also works.
    public var baseURL: String = "https://api.openai.com/v1"
    /// "none" | "low" | "medium" | "high" (| "xhigh" | "max"). Only sent when the model accepts it
    /// (`ModelCapabilities.for(model).allowedEfforts`); GPT-6 Luna/Sol always get "none".
    public var reasoningEffort: String = "none"
    /// Changes are always previewed; when false the assistant's proposals are applied
    /// immediately (with Undo).
    public var requireApproval: Bool = true
    /// How many days of schedule are pre-loaded into the prompt (today + N-1).
    public var contextDays: Int = 1
    /// Task notes are only sent to the model when this is on.
    public var shareNotes: Bool = false
    /// Set once the user accepted the data-sharing disclosure (App Review 5.1.2(i)).
    public var consentGiven: Bool = false

    /// Cheapest current OpenAI model with tool calling (verified 2026-11-09).
    public static let defaultModel = "gpt-6-luna"
    public static let modelPresets = ["gpt-6-luna", "gpt-5.6-luna", "gpt-5.4-mini", "gpt-6-sol", "gpt-5.6-terra"]
    /// Retired or retiring (2026-10-23 … 2027-01-14) ids that migrate to `defaultModel` on load.
    public static let retiredModels: Set<String> = ["gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-4.1-mini", "gpt-4o-mini", "gpt-4.1-nano", "o4-mini", "o3-mini"]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AssistantSettings()
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        if Self.retiredModels.contains(model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) { model = Self.defaultModel }
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? d.baseURL
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort) ?? d.reasoningEffort
        // No current small model supports "minimal"; OpenAI's guidance is to start with "low".
        if reasoningEffort == "minimal" { reasoningEffort = "low" }
        requireApproval = try c.decodeIfPresent(Bool.self, forKey: .requireApproval) ?? d.requireApproval
        contextDays = try c.decodeIfPresent(Int.self, forKey: .contextDays) ?? d.contextDays
        shareNotes = try c.decodeIfPresent(Bool.self, forKey: .shareNotes) ?? d.shareNotes
        consentGiven = try c.decodeIfPresent(Bool.self, forKey: .consentGiven) ?? d.consentGiven
    }

    private enum CodingKeys: String, CodingKey {
        case model, baseURL, reasoningEffort, requireApproval, contextDays, shareNotes, consentGiven
    }
}
