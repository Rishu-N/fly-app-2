import Foundation

/// Plan-vs-reality statistics for the Insights screen and the assistant's daily review.
/// Pure and cheap: one pass over the tasks of the requested days.
public struct DayInsights: Equatable, Sendable, Identifiable {
    public var day: DayKey
    public var plannedMinutes: Int
    /// Actual timer time (excludes pauses) of completed + cancelled tasks.
    public var focusedMinutes: Int
    public var completed: Int
    public var cancelled: Int
    public var skipped: Int
    public var missed: Int
    public var total: Int
    /// Started within ±`onTimeTolerance` of the planned start.
    public var onTimeStarts: Int
    public var startedCount: Int
    /// Average (actual start − planned start) in minutes over started tasks; negative = early.
    public var averageStartDriftMinutes: Double
    /// Minutes spent beyond the planned duration (sum over completed tasks).
    public var overrunMinutes: Int
    public var focusedMinutesByCategory: [TaskCategory: Int]

    public var id: DayKey { day }

    public var completionRate: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    public var onTimeRate: Double { startedCount == 0 ? 0 : Double(onTimeStarts) / Double(startedCount) }
}

public struct RangeInsights: Equatable, Sendable {
    public var days: [DayInsights]
    /// Consecutive days, ending with the last day in range (or the day before it if that day
    /// has nothing completed yet), with at least one completed block.
    public var streak: Int

    public var focusedMinutes: Int { days.reduce(0) { $0 + $1.focusedMinutes } }
    public var plannedMinutes: Int { days.reduce(0) { $0 + $1.plannedMinutes } }
    public var completed: Int { days.reduce(0) { $0 + $1.completed } }
    public var total: Int { days.reduce(0) { $0 + $1.total } }
    public var completionRate: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    public var onTimeRate: Double {
        let started = days.reduce(0) { $0 + $1.startedCount }
        return started == 0 ? 0 : Double(days.reduce(0) { $0 + $1.onTimeStarts }) / Double(started)
    }
    public var averageStartDriftMinutes: Double {
        let started = days.reduce(0) { $0 + $1.startedCount }
        guard started > 0 else { return 0 }
        return days.reduce(0) { $0 + $1.averageStartDriftMinutes * Double($1.startedCount) } / Double(started)
    }
    public var focusedMinutesByCategory: [TaskCategory: Int] {
        days.reduce(into: [:]) { acc, d in
            for (k, v) in d.focusedMinutesByCategory { acc[k, default: 0] += v }
        }
    }
    /// The category with the most focused minutes.
    public var topCategory: TaskCategory? {
        focusedMinutesByCategory.max { $0.value < $1.value }?.key
    }
}

public enum InsightsEngine {
    public static let onTimeTolerance: TimeInterval = 5 * 60

    public static func day(_ day: DayKey, tasks: [PlanTask], now: Date) -> DayInsights {
        var d = DayInsights(day: day, plannedMinutes: 0, focusedMinutes: 0, completed: 0, cancelled: 0, skipped: 0,
                            missed: 0, total: 0, onTimeStarts: 0, startedCount: 0, averageStartDriftMinutes: 0,
                            overrunMinutes: 0, focusedMinutesByCategory: [:])
        var driftSum: Double = 0
        for task in tasks {
            d.total += 1
            d.plannedMinutes += task.durationMinutes
            switch task.phase(at: now) {
            case .completed: d.completed += 1
            case .cancelled: d.cancelled += 1
            case .skipped: d.skipped += 1
            case .missed: d.missed += 1
            default: break
            }
            guard let session = task.session else { continue }
            d.startedCount += 1
            let drift = session.startedAt.timeIntervalSince(task.start)
            driftSum += drift / 60
            if abs(drift) <= onTimeTolerance { d.onTimeStarts += 1 }
            let elapsedMinutes = Int((session.elapsed(at: now) / 60).rounded())
            if task.status == .completed || task.status == .cancelled || task.status.isActive {
                d.focusedMinutes += elapsedMinutes
                d.focusedMinutesByCategory[task.category, default: 0] += elapsedMinutes
            }
            if task.status == .completed {
                d.overrunMinutes += max(0, Int(((session.elapsed(at: now) - task.duration) / 60).rounded()))
            }
        }
        d.averageStartDriftMinutes = d.startedCount == 0 ? 0 : driftSum / Double(d.startedCount)
        return d
    }

    /// - Parameter tasksForDay: provides the tasks of a day (e.g. `store.tasks(on:)`).
    public static func range(endingOn last: DayKey, days count: Int, calendar: Calendar, now: Date,
                             tasksForDay: (DayKey) -> [PlanTask]) -> RangeInsights {
        let n = max(1, count)
        let days = (0..<n).reversed().map { offset -> DayInsights in
            let key = last.adding(days: -offset, calendar: calendar)
            return day(key, tasks: tasksForDay(key), now: now)
        }
        // Streak: today counts only once something is done; otherwise start from yesterday.
        var streak = 0
        var cursor = last
        if (days.last?.completed ?? 0) == 0 { cursor = last.adding(days: -1, calendar: calendar) }
        var guardCount = 0
        while guardCount < 366 {
            let tasks = tasksForDay(cursor)
            guard tasks.contains(where: { $0.status == .completed }) else { break }
            streak += 1
            cursor = cursor.adding(days: -1, calendar: calendar)
            guardCount += 1
        }
        return RangeInsights(days: days, streak: streak)
    }
}
