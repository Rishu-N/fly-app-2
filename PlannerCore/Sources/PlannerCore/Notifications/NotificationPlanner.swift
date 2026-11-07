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

    /// Stable, content-addressed identifier: `<kind>.<task>.<epoch>.<content hash>`. It changes
    /// when the fire time *or* the visible content changes (so a rename updates the pending
    /// request) and never depends on `now` (so resyncs don't create duplicates).
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
                specs.append(make(.timerEnded, "timer", task: active, epochDate: end, fire: end,
                                  title: "Time's up · \(active.title)",
                                  body: "Mark it done, or add 5 minutes.",
                                  thread: end, timeSensitive: settings.timeSensitiveReminders, calendar: calendar))
            }
            let nudge = end.addingTimeInterval(10 * 60)
            if nudge > now {
                specs.append(make(.overrunNudge, "nudge", task: active, epochDate: nudge, fire: nudge,
                                  title: "Still on \(active.title)?",
                                  body: "You're 10 min over. Wrap up or extend.",
                                  thread: nudge, timeSensitive: false, calendar: calendar))
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
            let fire = task.start.addingTimeInterval(-TimeInterval(lead) * 60)
            let window = "\(timeFormatter(task.start))–\(timeFormatter(task.end))"
            let body = lead == 0
                ? "\(window) · \(formatDuration(task.durationMinutes)). Tap Start when you begin."
                : "\(window) · \(formatDuration(task.durationMinutes)). Start early — the timer runs the full block."
            if fire > now {
                let title: String = lead == 0 ? "Now · \(task.title)" : "\(task.title) in \(lead) min"
                specs.append(make(.leadReminder, "lead", task: task, epochDate: task.start, fire: fire,
                                  title: title, body: body, thread: task.start,
                                  timeSensitive: settings.timeSensitiveReminders, calendar: calendar))
                leadCount += 1
            } else if now.timeIntervalSince(task.updatedAt) < catchUpWindow, task.start.timeIntervalSince(now) > 30 {
                // Created/edited inside its lead window: one catch-up with the real minutes left.
                // Its id has no content hash, so later resyncs (and the delivered-filter) never
                // repeat it.
                let minutes = Int((task.start.timeIntervalSince(now) / 60).rounded(.up))
                var spec = make(.leadReminder, "lead", task: task, epochDate: task.start, fire: now.addingTimeInterval(1),
                                title: "\(task.title) in \(minutes) min", body: body, thread: task.start,
                                timeSensitive: settings.timeSensitiveReminders, calendar: calendar)
                spec.id = "lead.\(task.id.uuidString).\(Int(task.start.timeIntervalSince1970)).catchup"
                specs.append(spec)
                leadCount += 1
            }
        }
        return specs
    }

    /// Tasks edited this recently inside their lead window get one catch-up reminder.
    public static let catchUpWindow: TimeInterval = 180

    private static func make(
        _ kind: NotificationSpec.Kind, _ prefix: String, task: PlanTask, epochDate: Date, fire: Date,
        title: String, body: String, thread: Date, timeSensitive: Bool, calendar: Calendar
    ) -> NotificationSpec {
        let fingerprint = StableHash.short("\(title)|\(body)|\(timeSensitive)|\(Int(fire.timeIntervalSince1970))")
        return NotificationSpec(
            id: "\(prefix).\(task.id.uuidString).\(Int(epochDate.timeIntervalSince1970)).\(fingerprint)",
            kind: kind,
            taskID: task.id,
            fireDate: fire,
            title: title,
            body: body,
            threadID: "day-\(DayKey(thread, calendar: calendar))",
            timeSensitive: timeSensitive
        )
    }

    /// Minimal diff between desired specs and currently pending identifiers. Anything already
    /// delivered is never re-added.
    public static func diff(
        desired: [NotificationSpec],
        pendingIDs: Set<String>,
        deliveredIDs: Set<String> = [],
        ownedPrefixes: [String] = ["lead.", "timer.", "nudge."]
    ) -> (add: [NotificationSpec], removeIDs: [String]) {
        let desiredIDs = Set(desired.map(\.id))
        let add = desired.filter { !pendingIDs.contains($0.id) && !deliveredIDs.contains($0.id) }
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
