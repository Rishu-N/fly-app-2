import Foundation

/// Executes tool calls against the store. Read tools return compact text; write tools stage
/// `ProposalItem`s and return a short machine-readable acknowledgement for the model.
@MainActor
public struct ToolExecutor {
    public let store: TaskStore
    public let settings: PlannerSettings
    public let now: Date
    public let shareNotes: Bool
    let codec: LocalTimeCodec

    public init(store: TaskStore, settings: PlannerSettings, now: Date, shareNotes: Bool) {
        self.store = store
        self.settings = settings
        self.now = now
        self.shareNotes = shareNotes
        self.codec = LocalTimeCodec(calendar: store.calendar)
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

    private func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
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
        let payload: JSONValue = [
            "columns": "id|start|minutes|title|category|state|flags",
            "rows": .array(rows.map { .string($0) }),
            "count": .number(Double(rows.count)),
        ]
        return payload.serialized()
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
                let free = ScheduleMath.freeSlots(in: DateInterval(start: clippedStart, end: clippedEnd), tasks: tasks, minimumMinutes: duration, now: now)
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

    public func stage(_ tool: AssistantTool, args: JSONValue, into proposal: inout Proposal, refs: inout TaskRefRegistry) -> String {
        var staged: [ProposalItem] = []
        var errors: [String] = []

        switch tool {
        case .createTasks:
            for entry in args["tasks"]?.array ?? [] {
                guard let title = entry["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                    errors.append("missing title"); continue
                }
                guard let startRaw = entry["start"]?.string, let parsed = codec.parse(startRaw), parsed.hasTime else {
                    errors.append("\(title): start must be YYYY-MM-DDTHH:MM"); continue
                }
                let duration = min(720, max(1, entry["duration_minutes"]?.int ?? settings.defaultDurationMinutes))
                let category = entry["category"]?.string.flatMap(TaskCategory.init(loose:)) ?? TaskCategory.guess(fromTitle: title)
                let notes = entry["notes"]?.string ?? ""
                let lead = entry["reminder_minutes"]?.int
                if let rep = entry["repeat"], let rule = parseRepeat(rep) {
                    let c = calendar.dateComponents([.hour, .minute], from: parsed.date)
                    let series = TaskSeries(
                        title: title, notes: notes, category: category, durationMinutes: duration,
                        leadTimeMinutes: lead, hour: c.hour ?? 9, minute: c.minute ?? 0, rule: rule,
                        firstDay: DayKey(parsed.date, calendar: calendar)
                    )
                    let preview = series.makeOccurrence(on: DayKey(parsed.date, calendar: calendar), calendar: calendar, now: now)
                    staged.append(ProposalItem(kind: .addRoutine, after: preview, series: series, notes: [rule.label]))
                } else {
                    let task = PlanTask(
                        title: title, notes: notes, start: parsed.date, durationMinutes: duration,
                        category: category, leadTimeMinutes: lead, source: .assistant, createdAt: now
                    )
                    staged.append(ProposalItem(kind: .add, after: task))
                }
            }

        case .updateTasks:
            for entry in args["updates"]?.array ?? [] {
                guard let ref = entry["id"]?.string, let id = refs.id(for: ref), let existing = currentVersion(of: id, in: proposal) else {
                    errors.append("unknown id \(entry["id"]?.string ?? "?") — call list_tasks first"); continue
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
                if let lead = entry["reminder_minutes"]?.int, lead != t.leadTimeMinutes { t.leadTimeMinutes = lead; edited = true }
                guard moved || edited else { continue }
                if t.status.isClosed, moved { errors.append("\(ref) is already \(t.status.rawValue); not moved"); continue }
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
            let subset = Set((args["task_ids"]?.array ?? []).compactMap { $0.string.flatMap { refs.id(for: $0) } })
            let candidates = store.tasks(on: day).filter { $0.status == .planned && $0.start >= after && (subset.isEmpty || subset.contains($0.id)) }
            for task in candidates {
                var t = currentVersion(of: task.id, in: proposal) ?? task
                t.start = t.start.addingTimeInterval(TimeInterval(minutes * 60))
                staged.append(ProposalItem(kind: .move, before: task, after: t))
            }
            if candidates.isEmpty { errors.append("no not-started tasks on \(day) after \(afterRaw)") }

        case .deleteTasks:
            let reason = args["reason"]?.string
            for raw in args["ids"]?.array ?? [] {
                guard let ref = raw.string, let id = refs.id(for: ref), let task = store.task(id) else {
                    errors.append("unknown id \(raw.string ?? "?")"); continue
                }
                if task.status.isActive { errors.append("\(ref) is running; it can't be deleted"); continue }
                staged.append(ProposalItem(kind: .remove, before: task, notes: reason.map { [$0] } ?? []))
            }

        case .listTasks, .findFreeSlots, .askUser:
            return error("wrong_tool", "not a write tool")
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
            "status": .string(staged.isEmpty ? "error" : "proposed"),
            "change_set_id": .string(proposal.id),
            "items": .array(acks),
            "note": "Staged for the user's review. Nothing is saved until they tap Apply.",
        ]
        if !errors.isEmpty { result["errors"] = .array(errors.map { .string($0) }) }
        return JSONValue.object(result).serialized()
    }

    /// Applies the selected items of a proposal. Returns (undo entry id, created series ids, count).
    public func apply(_ proposal: Proposal) -> (undoID: UUID?, series: [UUID], count: Int) {
        var upserts: [PlanTask] = []
        var deletions: [UUID] = []
        var seriesIDs: [UUID] = []
        var count = 0
        for item in proposal.items where item.isSelected {
            switch item.kind {
            case .add, .move, .edit:
                if let after = item.after { upserts.append(after); count += 1 }
            case .remove:
                if let before = item.before { deletions.append(before.id); count += 1 }
            case .addRoutine:
                if let series = item.series {
                    store.addSeries(series, now: now)
                    seriesIDs.append(series.id)
                    count += 1
                }
            }
        }
        let label = proposal.summary.isEmpty ? "Assistant changes" : proposal.summary
        let changes = ChangeSet(label: label, upserts: upserts, deletions: deletions)
        var undoID: UUID?
        if !changes.isEmpty {
            store.apply(changes, now: now)
            undoID = store.undoStack.last?.id
        }
        return (undoID, seriesIDs, count)
    }

    // MARK: Helpers

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

    private func parseRepeat(_ value: JSONValue) -> RepeatRule? {
        guard let freq = value["frequency"]?.string?.lowercased() else { return nil }
        switch freq {
        case "daily": return .daily
        case "weekdays": return .weekdays
        case "weekly":
            let map = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
            let days = Set((value["weekdays"]?.array ?? []).compactMap { $0.string.flatMap { map[String($0.lowercased().prefix(3))] } })
            return .weekly(days: days.isEmpty ? [calendar.component(.weekday, from: now)] : days)
        default: return nil
        }
    }

    private func error(_ code: String, _ message: String) -> String {
        (["status": "error", "code": .string(code), "message": .string(message)] as JSONValue).serialized()
    }
}
