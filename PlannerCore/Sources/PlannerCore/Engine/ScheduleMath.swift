import Foundation

public enum ScheduleMath {
    /// Free intervals within `window` not covered by any *open or active* task, at least
    /// `minimumMinutes` long. Closed tasks free up their time.
    public static func freeSlots(
        in window: DateInterval,
        tasks: [PlanTask],
        minimumMinutes: Int = 15,
        now: Date? = nil
    ) -> [DateInterval] {
        var lower = window.start
        if let now, now > lower { lower = now }
        guard lower < window.end else { return [] }

        let busy = tasks
            .filter { !$0.status.isClosed }
            .map { task -> DateInterval in
                let start = task.session?.startedAt ?? task.start
                let end = max(start, now.map { task.expectedEnd(at: $0) } ?? task.end)
                return DateInterval(start: min(start, end), end: end)
            }
            .filter { $0.end > lower && $0.start < window.end }
            .sorted { $0.start < $1.start }

        var slots: [DateInterval] = []
        var cursor = lower
        for interval in busy {
            if interval.start > cursor {
                slots.append(DateInterval(start: cursor, end: min(interval.start, window.end)))
            }
            cursor = max(cursor, interval.end)
            if cursor >= window.end { break }
        }
        if cursor < window.end { slots.append(DateInterval(start: cursor, end: window.end)) }
        let minimum = TimeInterval(minimumMinutes) * 60
        return slots.filter { $0.duration >= minimum - 0.5 }
    }

    /// Pairs of overlapping open tasks (for conflict badges and AI validation).
    public static func overlaps(_ tasks: [PlanTask]) -> [(PlanTask, PlanTask)] {
        let open = tasks.filter { !$0.status.isClosed }.sorted(by: ScheduleEngine.chronological)
        var result: [(PlanTask, PlanTask)] = []
        for i in open.indices {
            var j = i + 1
            while j < open.count, open[j].start < open[i].end {
                result.append((open[i], open[j]))
                j += 1
            }
        }
        return result
    }

    /// "Running late" helper: pushes every open task that starts at or after `from` by `minutes`.
    /// Returns the updated copies (caller persists them as one undoable change).
    public static func shift(_ tasks: [PlanTask], startingAtOrAfter from: Date, byMinutes minutes: Int, now: Date) -> [PlanTask] {
        guard minutes != 0 else { return [] }
        return tasks
            .filter { $0.status == .planned && $0.start >= from }
            .map { task in
                var t = task
                t.start = task.start.addingTimeInterval(TimeInterval(minutes) * 60)
                t.updatedAt = now
                return t
            }
    }

    /// Rounds a date up to the next multiple of `minutes` (used for "start at next 5-minute mark").
    public static func roundUp(_ date: Date, toMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        let step = TimeInterval(max(1, minutes) * 60)
        let t = date.timeIntervalSinceReferenceDate
        let rounded = (t / step).rounded(.up) * step
        return Date(timeIntervalSinceReferenceDate: rounded)
    }
}

/// Materialises recurring series into concrete tasks for a rolling window.
public enum RecurrenceExpander {
    /// Returns new occurrences for `days` that don't exist yet.
    /// - Parameter existing: `(seriesID, day)` pairs already materialised (including deleted ones
    ///   are handled through `TaskSeries.excludedDays`).
    public static func occurrences(
        for series: [TaskSeries],
        days: [DayKey],
        existing: Set<SeriesDay>,
        calendar: Calendar,
        now: Date
    ) -> [PlanTask] {
        var result: [PlanTask] = []
        for s in series {
            for day in days where s.occurs(on: day, calendar: calendar) {
                let key = SeriesDay(seriesID: s.id, day: day)
                if !existing.contains(key) {
                    result.append(s.makeOccurrence(on: day, calendar: calendar, now: now))
                }
            }
        }
        return result
    }
}

public struct SeriesDay: Hashable, Sendable {
    public let seriesID: UUID
    public let day: DayKey
    public init(seriesID: UUID, day: DayKey) {
        self.seriesID = seriesID
        self.day = day
    }
}
