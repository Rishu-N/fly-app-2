import Foundation

/// Function-calling tools exposed to the model. Read tools run immediately; write tools only
/// *stage* changes into a `Proposal` the user reviews; `ask_user` pauses the loop for an answer.
public enum AssistantTool: String, CaseIterable, Sendable {
    case listTasks = "list_tasks"
    case findFreeSlots = "find_free_slots"
    case createTasks = "create_tasks"
    case updateTasks = "update_tasks"
    case shiftTasks = "shift_tasks"
    case deleteTasks = "delete_tasks"
    case askUser = "ask_user"

    public var isRead: Bool { self == .listTasks || self == .findFreeSlots }
    public var isWrite: Bool { [.createTasks, .updateTasks, .shiftTasks, .deleteTasks].contains(self) }

    /// Human status shown while the tool runs.
    public var statusLine: String {
        switch self {
        case .listTasks: "Checking your schedule…"
        case .findFreeSlots: "Looking for free time…"
        case .createTasks, .updateTasks, .shiftTasks, .deleteTasks: "Drafting changes…"
        case .askUser: "Waiting for your answer"
        }
    }

    public static let categoryEnum: JSONValue = .array(TaskCategory.allCases.map { .string($0.rawValue) })

    public static var definitions: [ToolDefinition] {
        let localDateTime: JSONValue = ["type": "string", "description": "Local time, ISO 8601 without offset: YYYY-MM-DDTHH:MM"]
        let localDateOrTime: JSONValue = ["type": "string", "description": "Local ISO date (YYYY-MM-DD) or datetime (YYYY-MM-DDTHH:MM)"]
        let repeatSchema: JSONValue = [
            "type": "object",
            "description": "Optional. Makes this a recurring routine.",
            "properties": [
                "frequency": ["type": "string", "enum": ["daily", "weekdays", "weekly"]],
                "weekdays": ["type": "array", "items": ["type": "string", "enum": ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]], "description": "For weekly"],
            ],
            "required": ["frequency"],
        ]
        return [
            ToolDefinition(
                name: AssistantTool.listTasks.rawValue,
                description: "List the user's tasks overlapping a local time range (max 14 days). Returns compact rows: id|start|minutes|title|category|state|flags.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "start": localDateOrTime,
                        "end": ["type": "string", "description": "Local ISO date or datetime, exclusive"],
                        "query": ["type": "string", "description": "Optional case-insensitive title/category filter"],
                        "include_done": ["type": "boolean", "description": "Include completed/cancelled/skipped (default true)"],
                    ],
                    "required": ["start", "end"],
                ]
            ),
            ToolDefinition(
                name: AssistantTool.findFreeSlots.rawValue,
                description: "Find free gaps of at least duration_minutes between start and end (max 14 days), inside the user's day window unless told otherwise. Earliest first.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "start": localDateOrTime,
                        "end": localDateOrTime,
                        "duration_minutes": ["type": "integer", "minimum": 5, "maximum": 720],
                        "count": ["type": "integer", "minimum": 1, "maximum": 10],
                        "within_day_window": ["type": "boolean", "description": "Default true"],
                    ],
                    "required": ["start", "end", "duration_minutes"],
                ]
            ),
            ToolDefinition(
                name: AssistantTool.createTasks.rawValue,
                description: "PROPOSE new tasks. Does not save — the user reviews and applies them in the app.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "tasks": [
                            "type": "array", "minItems": 1, "maxItems": 50,
                            "items": [
                                "type": "object",
                                "properties": [
                                    "title": ["type": "string", "maxLength": 120],
                                    "start": localDateTime,
                                    "duration_minutes": ["type": "integer", "minimum": 1, "maximum": 720],
                                    "category": ["type": "string", "enum": categoryEnum],
                                    "notes": ["type": "string", "maxLength": 500],
                                    "reminder_minutes": ["type": "integer", "minimum": 0, "maximum": 1440, "description": "Omit to use the user's default"],
                                    "repeat": repeatSchema,
                                ],
                                "required": ["title", "start", "duration_minutes"],
                            ],
                        ],
                        "summary": ["type": "string", "description": "One short line shown on the review card"],
                    ],
                    "required": ["tasks"],
                ]
            ),
            ToolDefinition(
                name: AssistantTool.updateTasks.rawValue,
                description: "PROPOSE edits to existing tasks (move, resize, rename, recategorise, reminder). Use ids from list_tasks or the context. Does not save.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "updates": [
                            "type": "array", "minItems": 1, "maxItems": 50,
                            "items": [
                                "type": "object",
                                "properties": [
                                    "id": ["type": "string"],
                                    "title": ["type": "string"],
                                    "start": localDateTime,
                                    "duration_minutes": ["type": "integer", "minimum": 1, "maximum": 720],
                                    "category": ["type": "string", "enum": categoryEnum],
                                    "notes": ["type": "string"],
                                    "reminder_minutes": ["type": "integer", "minimum": 0, "maximum": 1440],
                                ],
                                "required": ["id"],
                            ],
                        ],
                        "summary": ["type": "string"],
                    ],
                    "required": ["updates"],
                ]
            ),
            ToolDefinition(
                name: AssistantTool.shiftTasks.rawValue,
                description: "PROPOSE shifting not-started tasks on one day by N minutes (negative = earlier). Use for 'running late'.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "date": ["type": "string", "description": "Local ISO date YYYY-MM-DD"],
                        "after": ["type": "string", "description": "Local HH:MM — only tasks starting at/after this"],
                        "minutes": ["type": "integer", "minimum": -720, "maximum": 720],
                        "task_ids": ["type": "array", "items": ["type": "string"], "description": "Optional explicit subset"],
                    ],
                    "required": ["date", "after", "minutes"],
                ]
            ),
            ToolDefinition(
                name: AssistantTool.deleteTasks.rawValue,
                description: "PROPOSE deleting tasks. Does not delete — the user confirms. Never delete completed history unless explicitly asked.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "ids": ["type": "array", "minItems": 1, "maxItems": 50, "items": ["type": "string"]],
                        "reason": ["type": "string"],
                    ],
                    "required": ["ids"],
                ]
            ),
            ToolDefinition(
                name: AssistantTool.askUser.rawValue,
                description: "Ask ONE short clarifying question. The app shows the options as tappable chips (plus free text). The answer is returned as the tool result.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "question": ["type": "string", "maxLength": 140],
                        "options": ["type": "array", "minItems": 2, "maxItems": 4, "items": ["type": "string", "maxLength": 40]],
                        "allow_free_text": ["type": "boolean"],
                    ],
                    "required": ["question", "options"],
                ]
            ),
        ]
    }
}

// MARK: - Proposals

public struct ProposalItem: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case add, move, edit, remove, addRoutine }

    public var id: UUID
    public var kind: Kind
    public var before: PlanTask?
    public var after: PlanTask?
    public var series: TaskSeries?
    public var notes: [String]
    public var isSelected: Bool

    public init(kind: Kind, before: PlanTask? = nil, after: PlanTask? = nil, series: TaskSeries? = nil, notes: [String] = []) {
        self.id = UUID()
        self.kind = kind
        self.before = before
        self.after = after
        self.series = series
        self.notes = notes
        self.isSelected = true
    }

    /// The task this item is about (for de-duplicating edits to the same task).
    public var targetID: UUID? { before?.id ?? after?.id }
}

public struct Proposal: Identifiable, Codable, Hashable, Sendable {
    public enum State: Codable, Hashable, Sendable {
        case pending
        case applied(count: Int, total: Int)
        case discarded
        case undone
    }

    public var id: String
    public var summary: String
    public var items: [ProposalItem]
    public var state: State
    public var undoEntryID: UUID?
    public var createdSeriesIDs: [UUID]

    public init(id: String, summary: String = "", items: [ProposalItem] = []) {
        self.id = id
        self.summary = summary
        self.items = items
        self.state = .pending
        self.undoEntryID = nil
        self.createdSeriesIDs = []
    }

    public var selectedCount: Int { items.filter(\.isSelected).count }

    mutating func merge(_ item: ProposalItem) {
        if let target = item.targetID, item.kind != .add, item.kind != .addRoutine,
           let index = items.firstIndex(where: { $0.targetID == target && $0.kind != .add }) {
            var merged = item
            merged.before = items[index].before ?? item.before
            items[index] = merged
        } else {
            items.append(item)
        }
    }
}

/// Maps task UUIDs to short per-conversation references (`t1`, `t2`, …). Saves tokens and
/// prevents the model from inventing identifiers.
public struct TaskRefRegistry: Codable, Hashable, Sendable {
    private var refToID: [String: UUID] = [:]
    private var idToRef: [UUID: String] = [:]
    private var counter = 0

    public init() {}

    public mutating func ref(for id: UUID) -> String {
        if let r = idToRef[id] { return r }
        counter += 1
        let r = "t\(counter)"
        idToRef[id] = r
        refToID[r] = id
        return r
    }

    public func id(for ref: String) -> UUID? {
        let key = ref.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let id = refToID[key] { return id }
        return UUID(uuidString: ref)
    }
}

// MARK: - Local time formatting shared with the prompt

public struct LocalTimeCodec: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar) {
        var cal = calendar
        cal.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = cal
    }

    public func format(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    public func formatDay(_ date: Date) -> String {
        DayKey(date, calendar: calendar).description
    }

    public func formatClock(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Accepts `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM[:SS]`, `YYYY-MM-DD HH:MM`, optionally with a
    /// trailing `Z`/offset (ignored — the model is told to send local time).
    public func parse(_ raw: String) -> (date: Date, hasTime: Bool)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let plus = s.lastIndex(where: { $0 == "+" }), s.distance(from: s.startIndex, to: plus) >= 16 { s = String(s[..<plus]) }
        if s.hasSuffix("Z") { s.removeLast() }
        let parts = s.split(whereSeparator: { $0 == "T" || $0 == " " })
        guard let datePart = parts.first, let day = DayKey(string: String(datePart)) else { return nil }
        let base = day.startDate(calendar: calendar)
        guard parts.count > 1 else { return (base, false) }
        let timeParts = parts[1].split(separator: ":")
        guard timeParts.count >= 2, let h = Int(timeParts[0]), let m = Int(timeParts[1]), (0...24).contains(h), (0...59).contains(m) else { return nil }
        if h == 24 { return (calendar.date(byAdding: .day, value: 1, to: base) ?? base, true) }
        return (calendar.date(bySettingHour: h, minute: m, second: 0, of: base) ?? base, true)
    }
}
