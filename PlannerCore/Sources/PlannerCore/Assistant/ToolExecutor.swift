import Foundation

/// Executes tool calls against the store. Read tools return compact text; write tools stage
/// `ProposalItem`s and return a short machine-readable acknowledgement for the model.
@MainActor
public struct ToolExecutor {
    public let store: TaskStore
    public let settings: PlannerSettings
    public let now: Date
    public let shareNotes: Bool
    /// External calendar events (read-only busy time).
    public let busy: @MainActor (DateInterval) -> [BusyBlock]
    /// Event titles are only sent when the user allows it; otherwise events read as "Busy".
    public let shareEventTitles: Bool
    let codec: LocalTimeCodec

    public init(store: TaskStore, settings: PlannerSettings, now: Date, shareNotes: Bool,
                busy: @escaping @MainActor (DateInterval) -> [BusyBlock] = { _ in [] },
                shareEventTitles: Bool = false) {
        self.store = store
        self.settings = settings
        self.now = now
        self.shareNotes = shareNotes
        self.busy = busy
        self.shareEventTitles = shareEventTitles
        self.codec = LocalTimeCodec(calendar: store.calendar)
    }

    /// `e1|2026-11-07T15:00|30|Dentist|calendar` — timed events only, read-only.
    public func eventRows(in interval: DateInterval) -> [String] {
        busy(interval).filter { !$0.isAllDay }.sorted { $0.start < $1.start }.prefix(60).enumerated().map { index, event in
            let title = shareEventTitles ? sanitize(event.title) : "Busy"
            return "e\(index + 1)|\(codec.format(event.start))|\(event.durationMinutes)|\(title)|calendar"
        }
    }

    var calendar: Calendar { store.calendar }

    // MARK: Rows

    /// `t3|2026-11-07T14:00|60|Deep work|focus|upcoming|repeats`
    public func row(for task: PlanTask, refs: inout TaskRefRegistry) -> String {
        var flags: [String] = []
        if task.seriesID != nil { flags.append("repeats") }
        if let lead = task.leadTimeMinutes { flags.append("remind\(lead)m") }
        if !task.remind { flags.append("no-remind") }
        if task.status.isActive, let s = task.session {
            flags.append("ends \(codec.formatClock(s.projectedEnd(at: now)))")
        }
        var cols = [
            refs.ref(for: task.id),
            codec.format(task.start),
            String(task.durationMinutes),
            sanitize(task.title),
            task.category.rawValue,
            task.phase(at: now).rawValue,
        ]
        cols.append(flags.joined(separator: ","))
        var line = cols.joined(separator: "|")
        if shareNotes, !task.notes.isEmpty {
            line += "|notes: " + sanitize(String(task.notes.prefix(200)))
        }
        return line
    }

    /// Keeps user text inside one row: `|` would add a column, any line break a new line.
    private func sanitize(_ s: String) -> String {
        Self.flatten(s).replacingOccurrences(of: "|", with: "/")
    }

    /// Replaces every line break (`\n`, `\r`, CRLF, NEL, U+2028/2029, VT, FF) and other control
    /// character with a space. Works on scalars: "\r\n" is one `Character`, so a `"\n"` string
    /// replacement can leave the `\r` behind.
    nonisolated static func flatten(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            let breaks = CharacterSet.newlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
            scalars.append(breaks ? " " : scalar)
        }
        return String(scalars)
    }

    // MARK: Read tools

    public func listTasks(_ args: JSONValue, refs: inout TaskRefRegistry) -> String {
        guard let range = parseRange(args["start"]?.string, args["end"]?.string) else {
            return error("bad_range", "start/end must be local ISO dates or datetimes, end after start, max 14 days")
        }
        let includeDone = args["include_done"]?.bool ?? true
        let query = args["query"]?.string?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        var tasks = store.tasks(in: range)
        if !includeDone { tasks = tasks.filter { !$0.status.isClosed } }
        if !query.isEmpty {
            tasks = tasks.filter { $0.title.lowercased().contains(query) || $0.category.rawValue == query }
        }
        let rows = tasks.sorted(by: ScheduleEngine.chronological).prefix(200).map { row(for: $0, refs: &refs) }
        var payload: [String: JSONValue] = [
            "columns": "id|start|minutes|title|category|state|flags",
            "rows": .array(rows.map { .string($0) }),
            "count": .number(Double(rows.count)),
        ]
        if args["include_events"]?.bool ?? true {
            let events = eventRows(in: range)
            if !events.isEmpty {
                payload["calendar_events"] = .array(events.map { .string($0) })
                payload["calendar_note"] = "Read-only busy time from the user's calendar; plan around it, never edit it."
            }
        }
        return JSONValue.object(payload).serialized()
    }

    public func findFreeSlots(_ args: JSONValue) -> String {
        guard let range = parseRange(args["start"]?.string, args["end"]?.string) else {
            return error("bad_range", "start/end must be local ISO dates or datetimes, max 14 days")
        }
        guard let duration = args["duration_minutes"]?.int, duration >= 1 else {
            return error("bad_duration", "duration_minutes is required")
        }
        let count = min(10, max(1, args["count"]?.int ?? 3))
        let withinWindow = args["within_day_window"]?.bool ?? true
        var slots: [String] = []
        var day = DayKey(range.start, calendar: calendar)
        let lastDay = DayKey(range.end.addingTimeInterval(-1), calendar: calendar)
        while day <= lastDay, slots.count < count {
            let dayInterval = day.interval(calendar: calendar)
            var window = dayInterval
            if withinWindow {
                let start = calendar.date(bySettingHour: settings.dayStartHour, minute: 0, second: 0, of: dayInterval.start) ?? dayInterval.start
                let endHour = min(23, max(settings.dayStartHour + 1, settings.dayEndHour))
                let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: dayInterval.start) ?? dayInterval.end
                window = DateInterval(start: start, end: max(start, end))
            }
            let clippedStart = max(window.start, range.start)
            let clippedEnd = min(window.end, range.end)
            if clippedStart < clippedEnd {
                let tasks = store.tasks(in: DateInterval(start: clippedStart, end: clippedEnd))
                let slotWindow = DateInterval(start: clippedStart, end: clippedEnd)
                let free = ScheduleMath.freeSlots(in: slotWindow, tasks: tasks, busy: busy(slotWindow), minimumMinutes: duration, now: now)
                for slot in free where slots.count < count {
                    let start = ScheduleMath.roundUp(slot.start, toMinutes: 5, calendar: calendar)
                    guard slot.end.timeIntervalSince(start) >= TimeInterval(duration * 60) else { continue }
                    let minutes = Int(slot.end.timeIntervalSince(start) / 60)
                    slots.append("\(codec.format(start))–\(codec.formatClock(slot.end)) (\(minutes)m free)")
                }
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return (["slots": .array(slots.map { .string($0) })] as JSONValue).serialized()
    }

    // MARK: Write tools (staging)

    /// Rows accepted per write call (the schema's `maxItems`) and items per change set.
    public static let maxItemsPerCall = 50
    public static let maxItemsPerProposal = 100

    public func stage(_ tool: AssistantTool, args: JSONValue, into proposal: inout Proposal, refs: inout TaskRefRegistry) -> String {
        var staged: [ProposalItem] = []
        var errors: [String] = []

        /// The rows of `key` this call may stage, with an error for the rest.
        func rows(_ key: String) -> ArraySlice<JSONValue> {
            let all = args[key]?.array ?? []
            let room = max(0, Self.maxItemsPerProposal - proposal.items.count)
            let allowed = min(Self.maxItemsPerCall, room)
            if all.count > allowed {
                let left = all.count - allowed
                errors.append(allowed < Self.maxItemsPerCall
                    ? "this change set is full (\(Self.maxItemsPerProposal) items); \(left) rows were not staged — ask the user to apply it first"
                    : "at most \(Self.maxItemsPerCall) rows per call; \(left) rows were not staged — send them in another call")
            }
            return all.prefix(allowed)
        }

        switch tool {
        case .createTasks:
            for entry in rows("tasks") {
                guard let title = entry["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                    errors.append("missing title"); continue
                }
                guard let startRaw = entry["start"]?.string, let parsed = codec.parse(startRaw), parsed.hasTime else {
                    errors.append("\(title): start must be YYYY-MM-DDTHH:MM"); continue
                }
                let duration = min(720, max(1, entry["duration_minutes"]?.int ?? settings.defaultDurationMinutes))
                let category = entry["category"]?.string.flatMap(TaskCategory.init(loose:)) ?? TaskCategory.guess(fromTitle: title)
                let notes = entry["notes"]?.string ?? ""
                let lead = entry["reminder_minutes"]?.int.map { min(1440, max(0, $0)) }
                // (Explicit: JSONValue is ExpressibleByNilLiteral, so `? nil : $0` would yield `.null`.)
                var repeatArg: JSONValue? = entry["repeat"]
                if let r = repeatArg, r.isNull || r["frequency"]?.string?.lowercased() == "none" { repeatArg = Optional.none }
                if let repeatArg {
                    guard let rule = parseRepeat(repeatArg, startingOn: parsed.date) else {
                        errors.append("\(title): repeat.frequency must be daily, weekdays or weekly"); continue
                    }
                    let c = calendar.dateComponents([.hour, .minute], from: parsed.date)
                    let firstDay = DayKey(parsed.date, calendar: calendar)
                    let series = TaskSeries(
                        title: title, notes: notes, category: category, durationMinutes: duration,
                        leadTimeMinutes: lead, hour: c.hour ?? 9, minute: c.minute ?? 0, rule: rule,
                        firstDay: firstDay
                    )
                    if let duplicate = proposal.items.first(where: { $0.kind == .addRoutine && $0.series.map { Self.sameRoutine($0, series) } == true }) {
                        staged.append(duplicate); continue
                    }
                    // Preview the first day the routine actually occurs (a weekday routine that
                    // "starts" on a Sunday first happens on Monday).
                    let firstOccurrence = (0..<14).lazy.map { firstDay.adding(days: $0, calendar: calendar) }
                        .first { series.occurs(on: $0, calendar: calendar) } ?? firstDay
                    let preview = series.makeOccurrence(on: firstOccurrence, calendar: calendar, now: now)
                    staged.append(ProposalItem(kind: .addRoutine, after: preview, series: series, notes: [rule.label]))
                } else {
                    // Models often resend the whole batch after one row fails: the same title at the
                    // same start replaces the earlier row instead of adding a duplicate.
                    let reuse = proposal.items.first { $0.kind == .add && $0.after.map { Self.sameRow($0, title: title, start: parsed.date) } == true }
                    let task = PlanTask(
                        id: reuse?.after?.id ?? UUID(),
                        title: title, notes: notes, start: parsed.date, durationMinutes: duration,
                        category: category, leadTimeMinutes: lead, source: .assistant, createdAt: now
                    )
                    staged.append(ProposalItem(kind: .add, after: task))
                }
            }

        case .updateTasks:
            for entry in rows("updates") {
                guard let ref = entry["id"]?.string, let id = refs.id(for: ref), let existing = currentVersion(of: id, in: proposal) else {
                    errors.append("unknown id \(entry["id"]?.string ?? "?") — call list_tasks first"); continue
                }
                if proposal.items.contains(where: { $0.kind == .addRoutine && $0.after?.id == id }) {
                    errors.append("\(ref) is a routine in this proposal; send create_tasks again to change it"); continue
                }
                var t = existing
                var moved = false
                var edited = false
                if let title = entry["title"]?.string, !title.isEmpty, title != t.title { t.title = title; edited = true }
                if let startRaw = entry["start"]?.string {
                    guard let parsed = codec.parse(startRaw), parsed.hasTime else {
                        errors.append("\(ref): start must be YYYY-MM-DDTHH:MM"); continue
                    }
                    if parsed.date != t.start { t.start = parsed.date; moved = true }
                }
                if let d = entry["duration_minutes"]?.int, d != t.durationMinutes { t.durationMinutes = min(720, max(1, d)); moved = true }
                if let c = entry["category"]?.string.flatMap(TaskCategory.init(loose:)), c != t.category { t.category = c; edited = true }
                if let n = entry["notes"]?.string, n != t.notes { t.notes = n; edited = true }
                if let lead = entry["reminder_minutes"]?.int, lead != t.leadTimeMinutes { t.leadTimeMinutes = min(1440, max(0, lead)); edited = true }
                guard moved || edited else { errors.append("\(ref): nothing to change"); continue }
                if t.status.isClosed, moved { errors.append("\(ref) is already \(t.status.rawValue); not moved"); continue }
                // Moving a running/paused block would never apply (and timers are the user's).
                if t.status.isActive, moved { errors.append("\(ref) is \(t.status.rawValue); only tasks that haven't started can be moved"); continue }
                let before = store.task(id) ?? existing
                staged.append(ProposalItem(kind: moved ? .move : .edit, before: before, after: t))
            }

        case .shiftTasks:
            guard let dateRaw = args["date"]?.string, let day = DayKey(string: dateRaw),
                  let minutes = args["minutes"]?.int, minutes != 0 else {
                return error("bad_args", "date (YYYY-MM-DD) and non-zero minutes are required")
            }
            let afterRaw = args["after"]?.string ?? "00:00"
            guard let after = codec.parse("\(day)T\(afterRaw)")?.date else { return error("bad_args", "after must be HH:MM") }
            let requested = (args["task_ids"]?.array ?? []).compactMap(\.string)
            var subset = Set<UUID>()
            for ref in requested {
                if let id = refs.id(for: ref) { subset.insert(id) } else { errors.append("unknown id \(ref)") }
            }
            // An explicit subset that resolves to nothing must not widen to "every task that day".
            if !requested.isEmpty, subset.isEmpty {
                return error("unknown_id", "none of task_ids is known — call list_tasks first; nothing was staged")
            }
            let candidates = store.tasks(on: day).filter { $0.status == .planned && $0.start >= after && (subset.isEmpty || subset.contains($0.id)) }
            for task in candidates {
                var t = currentVersion(of: task.id, in: proposal) ?? task
                t.start = t.start.addingTimeInterval(TimeInterval(minutes * 60))
                staged.append(ProposalItem(kind: .move, before: task, after: t))
            }
            if candidates.isEmpty { errors.append("no not-started tasks on \(day) after \(afterRaw)") }

        case .deleteTasks:
            let reason = args["reason"]?.string
            for raw in rows("ids") {
                guard let ref = raw.string, let id = refs.id(for: ref), let task = store.task(id) else {
                    errors.append("unknown id \(raw.string ?? "?")"); continue
                }
                if task.status.isActive { errors.append("\(ref) is running; it can't be deleted"); continue }
                staged.append(ProposalItem(kind: .remove, before: task, notes: reason.map { [$0] } ?? []))
            }

        case .listTasks, .findFreeSlots, .askUser:
            return error("wrong_tool", "not a write tool")
        }

        if staged.isEmpty {
            // Don't claim anything was staged (and don't hand out a change-set id) when nothing was.
            var result: [String: JSONValue] = ["status": "error", "code": "nothing_staged", "message": "Nothing was staged."]
            if !errors.isEmpty { result["errors"] = .array(errors.map { .string($0) }) }
            return JSONValue.object(result).serialized()
        }
        if let summary = args["summary"]?.string, !summary.isEmpty {
            proposal.summary = proposal.summary.isEmpty ? summary : proposal.summary
        }
        for item in staged { proposal.merge(item) }
        annotateConflicts(&proposal)

        var acks: [JSONValue] = []
        for item in staged {
            let task = item.after ?? item.before
            guard let task else { continue }
            let ref = refs.ref(for: task.id)
            let latest = proposal.items.first(where: { $0.targetID == task.id })
            acks.append([
                "ref": .string(ref),
                "change": .string(item.kind.rawValue),
                "summary": .string("\(sanitize(task.title)) \(codec.format(task.start))–\(codec.formatClock(task.end))"),
                "conflicts": .array((latest?.notes ?? []).filter { $0.hasPrefix("Overlaps") }.map { .string($0) }),
            ])
        }
        var result: [String: JSONValue] = [
            "status": "proposed",
            "change_set_id": .string(proposal.id),
            "items": .array(acks),
            "note": "Staged for the user's review. Nothing is saved until they tap Apply.",
        ]
        if !errors.isEmpty { result["errors"] = .array(errors.map { .string($0) }) }
        return JSONValue.object(result).serialized()
    }

    /// Applies the selected items of a proposal against the *current* store (plan fields only,
    /// so a timer can never be started, stopped or reset by the assistant). Moves/removals of a
    /// task that started or finished since it was proposed are skipped and reported.
    /// Returns (undo entry id, created series ids, applied count, skipped titles).
    public func apply(_ proposal: Proposal) -> (undoID: UUID?, series: [UUID], count: Int, skipped: [String]) {
        var upserts: [PlanTask] = []
        var deletions: [UUID] = []
        var seriesIDs: [UUID] = []
        var skipped: [String] = []
        var count = 0
        for item in proposal.items where item.isSelected {
            let current = item.before.flatMap { store.task($0.id) }
            switch item.kind {
            case .add:
                if let after = item.after { upserts.append(after); count += 1 }
            case .move, .edit:
                guard let after = item.after else { continue }
                guard let current else { skipped.append(after.title); continue }
                if item.kind == .move, current.status != .planned { skipped.append(current.title); continue }
                // Rebase: only the fields this item changes are written, so an edit the user made
                // after the proposal was staged (e.g. a rename) isn't overwritten.
                upserts.append(item.before.map { Self.rebase(after, from: $0, onto: current) } ?? after)
                count += 1
            case .remove:
                guard let current, !current.status.isActive else {
                    if let t = item.before { skipped.append(t.title) }
                    continue
                }
                deletions.append(current.id)
                count += 1
            case .addRoutine:
                if let series = item.series {
                    store.addSeries(series, now: now)
                    seriesIDs.append(series.id)
                    count += 1
                }
            }
        }
        let label = proposal.summary.isEmpty ? "Assistant changes" : proposal.summary
        let changes = ChangeSet(label: label, upserts: upserts, deletions: deletions, mode: .plan)
        var undoID: UUID?
        if !changes.isEmpty {
            store.apply(changes, now: now)
            undoID = store.lastUndoID
        }
        return (undoID, seriesIDs, count, skipped)
    }

    // MARK: Helpers

    /// `current` with every plan field that differs between `before` and `after` taken from `after`.
    nonisolated static func rebase(_ after: PlanTask, from before: PlanTask, onto current: PlanTask) -> PlanTask {
        var t = current
        if after.title != before.title { t.title = after.title }
        if after.notes != before.notes { t.notes = after.notes }
        if after.start != before.start { t.start = after.start }
        if after.durationMinutes != before.durationMinutes { t.durationMinutes = after.durationMinutes }
        if after.category != before.category { t.category = after.category }
        if after.leadTimeMinutes != before.leadTimeMinutes { t.leadTimeMinutes = after.leadTimeMinutes }
        if after.remind != before.remind { t.remind = after.remind }
        if after.checklist != before.checklist { t.checklist = after.checklist }
        return t
    }

    nonisolated static func sameRow(_ task: PlanTask, title: String, start: Date) -> Bool {
        task.start == start && task.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == title.lowercased()
    }

    nonisolated static func sameRoutine(_ a: TaskSeries, _ b: TaskSeries) -> Bool {
        a.title.lowercased() == b.title.lowercased() && a.hour == b.hour && a.minute == b.minute && a.rule == b.rule && a.firstDay == b.firstDay
    }

    private func currentVersion(of id: UUID, in proposal: Proposal) -> PlanTask? {
        if let staged = proposal.items.last(where: { $0.targetID == id && $0.kind != .remove })?.after { return staged }
        return store.task(id)
    }

    private func annotateConflicts(_ proposal: inout Proposal) {
        let removed = Set(proposal.items.filter { $0.kind == .remove && $0.isSelected }.compactMap(\.before?.id))
        let changed = Set(proposal.items.compactMap { $0.kind == .remove ? nil : $0.after?.id })
        for index in proposal.items.indices {
            guard proposal.items[index].kind != .remove, let task = proposal.items[index].after else { continue }
            var notes = proposal.items[index].notes.filter { !$0.hasPrefix("Overlaps") && $0 != "In the past" }
            let window = task.plannedInterval
            let existing = store.tasks(in: window).filter {
                !$0.status.isClosed && $0.id != task.id && !removed.contains($0.id) && !changed.contains($0.id)
            }
            let others = proposal.items.enumerated().compactMap { (i, other) -> PlanTask? in
                guard i != index, other.kind != .remove, let t = other.after, t.id != task.id else { return nil }
                return t
            }
            for other in existing + others where other.start < task.end && other.end > task.start {
                notes.append("Overlaps \(other.title) \(codec.formatClock(other.start))–\(codec.formatClock(other.end))")
            }
            for event in busy(window) where !event.isAllDay && event.start < task.end && event.end > task.start {
                let title = shareEventTitles ? event.title : "a calendar event"
                notes.append("Overlaps \(title) \(codec.formatClock(event.start))–\(codec.formatClock(event.end))")
            }
            if task.start < now.addingTimeInterval(-60), proposal.items[index].kind != .edit { notes.append("In the past") }
            proposal.items[index].notes = notes
        }
    }

    func parseRange(_ startRaw: String?, _ endRaw: String?) -> DateInterval? {
        guard let s = startRaw.flatMap(codec.parse), let e = endRaw.flatMap(codec.parse) else { return nil }
        var end = e.date
        // A date-only end is exclusive at midnight; if it equals the start day, include that day.
        if !e.hasTime, end <= s.date { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        guard end > s.date, end.timeIntervalSince(s.date) <= 15 * 86_400 else { return nil }
        return DateInterval(start: s.date, end: end)
    }

    /// A weekly rule without weekdays repeats on the weekday of `start` (not of today).
    private func parseRepeat(_ value: JSONValue, startingOn start: Date) -> RepeatRule? {
        guard let freq = value["frequency"]?.string?.lowercased() else { return nil }
        switch freq {
        case "daily": return .daily
        case "weekdays": return .weekdays
        case "weekly":
            let map = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
            let days = Set((value["weekdays"]?.array ?? []).compactMap { $0.string.flatMap { map[String($0.lowercased().prefix(3))] } })
            return .weekly(days: days.isEmpty ? [calendar.component(.weekday, from: start)] : days)
        default: return nil
        }
    }

    private func error(_ code: String, _ message: String) -> String {
        (["status": "error", "code": .string(code), "message": .string(message)] as JSONValue).serialized()
    }
}
