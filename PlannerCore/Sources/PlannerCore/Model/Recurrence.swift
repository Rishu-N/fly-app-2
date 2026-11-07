import Foundation

/// How a series repeats. Weekdays use `Calendar` numbering: 1 = Sunday … 7 = Saturday.
public enum RepeatRule: Codable, Hashable, Sendable {
    case daily
    case weekdays
    case weekly(days: Set<Int>)

    public func matches(_ day: DayKey, calendar: Calendar) -> Bool {
        let weekday = day.weekday(calendar: calendar)
        switch self {
        case .daily: return true
        case .weekdays: return (2...6).contains(weekday)
        case .weekly(let days): return days.contains(weekday)
        }
    }

    public var label: String {
        switch self {
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly(let days):
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let sorted = days.sorted().compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }
            return sorted.isEmpty ? "Weekly" : "Every " + sorted.joined(separator: ", ")
        }
    }

    /// Token used by the assistant tool schema: none | daily | weekdays | weekly.
    public var token: String {
        switch self {
        case .daily: "daily"
        case .weekdays: "weekdays"
        case .weekly: "weekly"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, days }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "daily": self = .daily
        case "weekdays": self = .weekdays
        default: self = .weekly(days: try c.decodeIfPresent(Set<Int>.self, forKey: .days) ?? [])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(token, forKey: .kind)
        if case .weekly(let days) = self { try c.encode(days.sorted(), forKey: .days) }
    }
}

/// A recurring template. Occurrences are materialised as ordinary `PlanTask`s for a rolling
/// window (see `RecurrenceExpander`) so every query, notification and timer path stays simple.
public struct TaskSeries: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var category: TaskCategory
    public var durationMinutes: Int
    public var leadTimeMinutes: Int?
    public var remind: Bool
    public var checklistTitles: [String]
    /// Local time of day.
    public var hour: Int
    public var minute: Int
    public var rule: RepeatRule
    public var firstDay: DayKey
    public var lastDay: DayKey?
    /// Days the user deleted a single occurrence of; never re-materialised.
    public var excludedDays: Set<DayKey>

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        category: TaskCategory,
        durationMinutes: Int,
        leadTimeMinutes: Int? = nil,
        remind: Bool = true,
        checklistTitles: [String] = [],
        hour: Int,
        minute: Int,
        rule: RepeatRule,
        firstDay: DayKey,
        lastDay: DayKey? = nil,
        excludedDays: Set<DayKey> = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.category = category
        self.durationMinutes = max(1, durationMinutes)
        self.leadTimeMinutes = leadTimeMinutes
        self.remind = remind
        self.checklistTitles = checklistTitles
        self.hour = hour
        self.minute = minute
        self.rule = rule
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.excludedDays = excludedDays
    }

    public func occurs(on day: DayKey, calendar: Calendar) -> Bool {
        guard day >= firstDay else { return false }
        if let lastDay, day > lastDay { return false }
        if excludedDays.contains(day) { return false }
        return rule.matches(day, calendar: calendar)
    }

    public func makeOccurrence(on day: DayKey, calendar: Calendar, now: Date = Date()) -> PlanTask {
        let base = day.startDate(calendar: calendar)
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        return PlanTask(
            id: UUID(),
            title: title,
            notes: notes,
            start: start,
            durationMinutes: durationMinutes,
            category: category,
            leadTimeMinutes: leadTimeMinutes,
            remind: remind,
            checklist: checklistTitles.map { ChecklistItem(title: $0) },
            seriesID: id,
            occurrenceDay: day,
            source: .recurrence,
            createdAt: now
        )
    }
}
