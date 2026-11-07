import Foundation

/// Everything the Home ("Now") screen needs, computed in one pass from a small slice of tasks.
public struct NowSnapshot: Equatable, Sendable {
    /// What the hero card shows.
    public enum Focus: Equatable, Sendable {
        /// A task is running or paused.
        case active(PlanTask)
        /// A planned task whose window contains now, waiting for Start.
        case due(PlanTask)
        /// Nothing scheduled right now; the next task starts at `next.start`.
        case gap(next: PlanTask)
        /// Nothing left today.
        case clear
    }

    public var focus: Focus
    /// The block right before the focus (done, cancelled, skipped or missed).
    public var previous: PlanTask?
    /// The next two open tasks after the focus.
    public var upcoming: [PlanTask]
    /// Open tasks whose window already passed without being started (today only).
    public var missedCount: Int
    /// Minutes the active task is projected to run past the next task's planned start.
    public var projectedLateMinutes: Int

    public var focusTask: PlanTask? {
        switch focus {
        case .active(let t), .due(let t): t
        case .gap(let next): next
        case .clear: nil
        }
    }
}

public enum ScheduleEngine {
    /// Builds the Home snapshot.
    ///
    /// - Parameter tasks: tasks around `now` (yesterday…tomorrow is plenty). Order doesn't matter.
    public static func snapshot(tasks: [PlanTask], now: Date, calendar: Calendar = .current) -> NowSnapshot {
        let sorted = tasks.sorted(by: Self.chronological)
        let active = sorted.first(where: { $0.status.isActive })

        // A planned task whose window contains now (earliest wins when blocks overlap).
        let due = sorted.first(where: { $0.status == .planned && $0.start <= now && now < $0.end })

        let focus: NowSnapshot.Focus
        let anchorStart: Date
        if let active {
            focus = .active(active)
            anchorStart = active.start
        } else if let due {
            focus = .due(due)
            anchorStart = due.start
        } else if let next = sorted.first(where: { $0.status == .planned && $0.start > now }),
                  calendar.isDate(next.start, inSameDayAs: now) || next.start.timeIntervalSince(now) < 6 * 3600 {
            focus = .gap(next: next)
            anchorStart = now
        } else {
            focus = .clear
            anchorStart = now
        }

        let focusID: UUID? = {
            switch focus {
            case .active(let t), .due(let t): return t.id
            case .gap(let n): return n.id
            case .clear: return nil
            }
        }()

        // Previous: the most recent block that started before the anchor (not the focus itself)
        // and is finished one way or another.
        let previous = sorted.last(where: { task in
            task.id != focusID
                && task.start <= anchorStart
                && (task.status.isClosed || (task.status == .planned && task.end <= now))
                && now.timeIntervalSince(task.end) < 18 * 3600
        })

        // Upcoming: next two open tasks after the focus.
        var upcoming: [PlanTask] = []
        for task in sorted where task.id != focusID && task.status == .planned {
            let after: Bool
            switch focus {
            case .gap(let next): after = task.start >= next.start
            case .active, .due: after = task.end > now
            case .clear: after = task.start > now
            }
            if after {
                upcoming.append(task)
                if upcoming.count == 2 { break }
            }
        }
        // In the gap state the hero shows `next`; the list continues after it.

        let missed = sorted.filter {
            $0.status == .planned && $0.end <= now && calendar.isDate($0.start, inSameDayAs: now)
        }.count

        var late = 0
        if let active, let nextStart = upcoming.first?.start {
            let projected = active.expectedEnd(at: now)
            if projected > nextStart { late = Int((projected.timeIntervalSince(nextStart) / 60).rounded(.up)) }
        }

        return NowSnapshot(
            focus: focus,
            previous: previous,
            upcoming: upcoming,
            missedCount: missed,
            projectedLateMinutes: late
        )
    }

    /// The next moment at which `snapshot` could change without any user action
    /// (a task window opening/closing, a timer hitting zero). The UI schedules a single
    /// refresh for this instant instead of polling.
    public static func nextBoundary(after now: Date, tasks: [PlanTask]) -> Date? {
        var best: Date?
        func consider(_ d: Date) {
            guard d > now else { return }
            if best == nil || d < best! { best = d }
        }
        for task in tasks {
            switch task.status {
            case .planned:
                consider(task.start)
                consider(task.end)
            case .running:
                if let s = task.session { consider(s.projectedEnd(at: now)) }
            default:
                break
            }
        }
        return best
    }

    static func chronological(_ a: PlanTask, _ b: PlanTask) -> Bool {
        if a.start != b.start { return a.start < b.start }
        if a.durationMinutes != b.durationMinutes { return a.durationMinutes < b.durationMinutes }
        return a.id.uuidString < b.id.uuidString
    }
}
