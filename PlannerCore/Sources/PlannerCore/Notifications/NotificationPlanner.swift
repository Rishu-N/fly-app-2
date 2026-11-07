import Foundation

/// A platform-neutral description of one local notification. The app maps these onto
/// `UNNotificationRequest`s and diffs them against what's already pending, so a change to one
/// task touches at most a couple of system requests.
public struct NotificationSpec: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        /// "Deep work in 5 min" — actions: Start now · Snooze 5m · Skip.
        case leadReminder
        /// "Time's up" when a running timer reaches zero — actions: Complete · +5 min.
        case timerEnded
        /// One gentle nudge 10 minutes into an overrun.
        case overrunNudge
    }

    /// Stable, content-addressed identifier: changes whenever the fire date changes, so the
    /// diff naturally replaces stale requests.
    public var id: String
    public var kind: Kind
    public var taskID: UUID
    public var fireDate: Date
    public var title: String
    public var body: String
    /// Used for notification grouping (one thread per day).
    public var threadID: String
    public var timeSensitive: Bool

    /// Notification category identifiers the app registers with actions.
    public static let categoryLead = "TASK_LEAD"
    public static let categoryTimer = "TASK_TIMER"

    public var categoryID: String {
        switch kind {
        case .leadReminder: Self.categoryLead
        case .timerEnded, .overrunNudge: Self.categoryTimer
        }
    }
}

public enum NotificationPlanner {
    /// iOS keeps at most 64 pending local notifications per app. Leave headroom for
    /// timer/AI notifications that are scheduled outside this plan.
    public static let reminderBudget = 56
    public static let horizonDays = 7

    public static func plan(
        tasks: [PlanTask],
        settings: PlannerSettings,
        now: Date,
        calendar: Calendar = .current,
        timeFormatter: (Date) -> String
    ) -> [NotificationSpec] {
        var specs: [NotificationSpec] = []
        let horizon = now.addingTimeInterval(TimeInterval(horizonDays) * 86_400)

        // Timer notifications for the active task always win budget.
        if let active = tasks.first(where: { $0.status == .running }), let session = active.session, settings.notifyWhenTimerEnds {
            let end = session.projectedEnd(at: now)
            if end > now {
                specs.append(NotificationSpec(
                    id: "timer.\(active.id.uuidString).\(Int(end.timeIntervalSince1970))",
                    kind: .timerEnded,
                    taskID: active.id,
                    fireDate: end,
                    title: "Time's up · \(active.title)",
                    body: "Mark it done, or add 5 minutes.",
                    threadID: "day-\(DayKey(end, calendar: calendar))",
                    timeSensitive: settings.timeSensitiveReminders
                ))
            }
            let nudge = end.addingTimeInterval(10 * 60)
            if nudge > now {
                specs.append(NotificationSpec(
                    id: "nudge.\(active.id.uuidString).\(Int(nudge.timeIntervalSince1970))",
                    kind: .overrunNudge,
                    taskID: active.id,
                    fireDate: nudge,
                    title: "Still on \(active.title)?",
                    body: "You're 10 min over. Wrap up or extend.",
                    threadID: "day-\(DayKey(nudge, calendar: calendar))",
                    timeSensitive: false
                ))
            }
        }

        guard settings.remindersEnabled else { return specs }

        let candidates = tasks
            .filter { $0.status == .planned && $0.start > now && $0.start <= horizon }
            .sorted(by: ScheduleEngine.chronological)

        var leadCount = 0
        for task in candidates {
            guard leadCount < reminderBudget else { break }
            guard let lead = task.effectiveLeadMinutes(defaultLead: settings.defaultLeadMinutes) else { continue }
            var fire = task.start.addingTimeInterval(-TimeInterval(lead) * 60)
            // If we're already inside the lead window, remind shortly (but never in the past).
            if fire <= now {
                guard task.start.timeIntervalSince(now) > 30 else { continue }
                fire = now.addingTimeInterval(1)
            }
            let window = "\(timeFormatter(task.start))–\(timeFormatter(task.end))"
            let title: String = lead == 0 ? "Now · \(task.title)" : "\(task.title) in \(lead) min"
            let body = lead == 0
                ? "\(window) · \(formatDuration(task.durationMinutes)). Tap Start when you begin."
                : "\(window) · \(formatDuration(task.durationMinutes)). Start early — the timer runs the full block."
            specs.append(NotificationSpec(
                id: "lead.\(task.id.uuidString).\(Int(fire.timeIntervalSince1970))",
                kind: .leadReminder,
                taskID: task.id,
                fireDate: fire,
                title: title,
                body: body,
                threadID: "day-\(DayKey(task.start, calendar: calendar))",
                timeSensitive: settings.timeSensitiveReminders
            ))
            leadCount += 1
        }
        return specs
    }

    /// Minimal diff between desired specs and currently pending identifiers.
    public static func diff(desired: [NotificationSpec], pendingIDs: Set<String>, ownedPrefixes: [String] = ["lead.", "timer.", "nudge."])
        -> (add: [NotificationSpec], removeIDs: [String])
    {
        let desiredIDs = Set(desired.map(\.id))
        let add = desired.filter { !pendingIDs.contains($0.id) }
        let remove = pendingIDs.filter { id in
            !desiredIDs.contains(id) && ownedPrefixes.contains(where: { id.hasPrefix($0) })
        }
        return (add, remove.sorted())
    }

    public static func taskID(fromNotificationID id: String) -> UUID? {
        let parts = id.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return UUID(uuidString: String(parts[1]))
    }
}

/// "45m", "1h", "1h 30m".
public func formatDuration(_ minutes: Int) -> String {
    let m = max(0, minutes)
    if m < 60 { return "\(m)m" }
    let h = m / 60, r = m % 60
    return r == 0 ? "\(h)h" : "\(h)h \(r)m"
}

/// "12:04" / "1:02:09" / "-3:10" for countdown labels where the system timer text can't be used.
public func formatClock(_ seconds: TimeInterval) -> String {
    let negative = seconds < 0
    let total = Int(abs(seconds).rounded(.down))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    let core = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    return negative ? "+" + core : core
}
