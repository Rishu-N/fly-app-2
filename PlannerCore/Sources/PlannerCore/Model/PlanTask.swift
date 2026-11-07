import Foundation

/// Lifecycle status of a scheduled block.
public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    /// Scheduled, not started yet (may be upcoming, current or missed — see `TaskPhase`).
    case planned
    /// Timer is running.
    case running
    /// Timer is paused.
    case paused
    /// User completed the task.
    case completed
    /// User abandoned the task after starting it (or cancelled it explicitly).
    case cancelled
    /// User chose not to do a task that was never started.
    case skipped

    public var isActive: Bool { self == .running || self == .paused }
    public var isClosed: Bool { self == .completed || self == .cancelled || self == .skipped }
    public var isOpen: Bool { self == .planned }
}

/// Where a task came from. Useful for analytics and for the assistant's undo UI.
public enum TaskSource: String, Codable, Sendable {
    case user
    case assistant
    case recurrence
    case quickAdd
}

public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

/// A single time block on the user's schedule.
///
/// `start` + `durationMinutes` is the *plan*. `session` is what actually happened once the
/// user pressed Start. The timer always runs for the planned duration from the moment the
/// user starts, regardless of the clock (2:00–3:00 started at 1:58 → timer ends 2:58).
public struct PlanTask: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var start: Date
    public var durationMinutes: Int
    public var category: TaskCategory
    /// Minutes before `start` to remind. `nil` → use the global default from settings.
    public var leadTimeMinutes: Int?
    /// Master switch for this task's reminder.
    public var remind: Bool
    public var checklist: [ChecklistItem]
    public var status: TaskStatus
    public var session: TimerSession?
    /// Set when the task was materialised from a recurring series.
    public var seriesID: UUID?
    public var occurrenceDay: DayKey?
    public var source: TaskSource
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        start: Date,
        durationMinutes: Int,
        category: TaskCategory = .focus,
        leadTimeMinutes: Int? = nil,
        remind: Bool = true,
        checklist: [ChecklistItem] = [],
        status: TaskStatus = .planned,
        session: TimerSession? = nil,
        seriesID: UUID? = nil,
        occurrenceDay: DayKey? = nil,
        source: TaskSource = .user,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.start = start
        self.durationMinutes = max(1, durationMinutes)
        self.category = category
        self.leadTimeMinutes = leadTimeMinutes
        self.remind = remind
        self.checklist = checklist
        self.status = status
        self.session = session
        self.seriesID = seriesID
        self.occurrenceDay = occurrenceDay
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    // MARK: Derived

    public var duration: TimeInterval { TimeInterval(durationMinutes) * 60 }
    public var end: Date { start.addingTimeInterval(duration) }
    public var plannedInterval: DateInterval { DateInterval(start: start, duration: duration) }

    public func day(calendar: Calendar = .current) -> DayKey { DayKey(start, calendar: calendar) }

    /// Effective reminder lead time, or `nil` if this task should not remind.
    public func effectiveLeadMinutes(defaultLead: Int) -> Int? {
        guard remind else { return nil }
        return max(0, leadTimeMinutes ?? defaultLead)
    }

    /// When the block is expected to end, taking a live timer into account. An overrunning
    /// task is expected to end no earlier than `now`.
    public func expectedEnd(at now: Date) -> Date {
        if let session, status.isActive { return max(session.projectedEnd(at: now), now) }
        if let session, let ended = session.endedAt { return ended }
        return end
    }

    /// Fine-grained phase for presentation (adds `upcoming/now/missed` to `planned`).
    public func phase(at now: Date) -> TaskPhase {
        switch status {
        case .running:
            if let session, session.isOverrun(at: now) { return .overrun }
            return .running
        case .paused: return .paused
        case .completed: return .completed
        case .cancelled: return .cancelled
        case .skipped: return .skipped
        case .planned:
            if now < start { return .upcoming }
            if now < end { return .due }
            return .missed
        }
    }

    // MARK: Codable (tolerant decoding so new fields never break old files)

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, start, durationMinutes, category, leadTimeMinutes, remind, checklist
        case status, session, seriesID, occurrenceDay, source, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        start = try c.decode(Date.self, forKey: .start)
        durationMinutes = max(1, try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 30)
        category = (try? c.decodeIfPresent(TaskCategory.self, forKey: .category)) ?? .focus
        leadTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .leadTimeMinutes)
        remind = try c.decodeIfPresent(Bool.self, forKey: .remind) ?? true
        checklist = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
        status = (try? c.decodeIfPresent(TaskStatus.self, forKey: .status)) ?? .planned
        session = try c.decodeIfPresent(TimerSession.self, forKey: .session)
        seriesID = try c.decodeIfPresent(UUID.self, forKey: .seriesID)
        occurrenceDay = try c.decodeIfPresent(DayKey.self, forKey: .occurrenceDay)
        source = (try? c.decodeIfPresent(TaskSource.self, forKey: .source)) ?? .user
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? start
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        if !notes.isEmpty { try c.encode(notes, forKey: .notes) }
        try c.encode(start, forKey: .start)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(leadTimeMinutes, forKey: .leadTimeMinutes)
        if !remind { try c.encode(remind, forKey: .remind) }
        if !checklist.isEmpty { try c.encode(checklist, forKey: .checklist) }
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(session, forKey: .session)
        try c.encodeIfPresent(seriesID, forKey: .seriesID)
        try c.encodeIfPresent(occurrenceDay, forKey: .occurrenceDay)
        if source != .user { try c.encode(source, forKey: .source) }
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Presentation phase derived from status + clock.
public enum TaskPhase: String, Sendable {
    case upcoming   // planned, starts in the future
    case due        // planned, its window contains now, not started
    case missed     // planned, window passed, never started
    case running
    case paused
    case overrun    // running past the timer
    case completed
    case cancelled
    case skipped

    public var isDone: Bool { self == .completed || self == .cancelled || self == .skipped }
}
