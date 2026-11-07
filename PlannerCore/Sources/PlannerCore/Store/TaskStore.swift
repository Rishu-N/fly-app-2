import Foundation
import Observation

/// How to resolve starting a task while another one is active (only one timer at a time).
public enum ActiveConflictResolution: Sendable, Equatable {
    case completeOther
    case cancelOther
}

/// The single source of truth for the schedule.
///
/// Performance notes:
/// - All tasks live in memory as value types (`[UUID: PlanTask]`); a heavy user has a few
///   thousand. Day queries go through `idsByDay` + a per-day sorted cache, so a day lookup is
///   O(tasks that day), not O(all tasks).
/// - Writes mark only the touched month dirty and are flushed after a short debounce on the
///   persistence actor (off the main thread).
/// - Older months are loaded lazily the first time a view asks for them.
@MainActor
@Observable
public final class TaskStore {
    public private(set) var tasksByID: [UUID: PlanTask] = [:]
    public private(set) var series: [UUID: TaskSeries] = [:]
    public private(set) var isLoaded = false
    /// Bumped on every mutation — cheap to observe for "something changed".
    public private(set) var revision = 0
    public private(set) var undoStack: [UndoEntry] = []

    @ObservationIgnored public var calendar: Calendar
    @ObservationIgnored public var onChange: (@MainActor (StoreChange) -> Void)?
    @ObservationIgnored public var flushDelay: Duration = .milliseconds(350)
    @ObservationIgnored public var recurrenceWindowDays = 14

    @ObservationIgnored private let persistence: PlannerPersistence
    @ObservationIgnored private var idsByDay: [DayKey: Set<UUID>] = [:]
    @ObservationIgnored private var dayCache: [DayKey: [PlanTask]] = [:]
    @ObservationIgnored private var loadedMonths: Set<MonthKey> = []
    @ObservationIgnored private var dirtyMonths: Set<MonthKey> = []
    @ObservationIgnored private var seriesDirty = false
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var materializedThrough: DayKey?

    public init(persistence: PlannerPersistence, calendar: Calendar = .autoupdatingCurrent) {
        self.persistence = persistence
        self.calendar = calendar
    }

    // MARK: - Loading

    /// Loads the working window (2 months back → all future months) and series, then
    /// materialises recurring occurrences. Older months load on demand via `ensureLoaded`.
    public func bootstrap(now: Date = Date()) async {
        guard !isLoaded else { return }
        let current = MonthKey(now, calendar: calendar)
        let earliest = current.adding(months: -2)
        let months = (try? await persistence.availableMonths()) ?? []
        let window = months.filter { $0 >= earliest }
        var loaded: [PlanTask] = []
        await withTaskGroup(of: [PlanTask].self) { group in
            for month in window {
                group.addTask { [persistence] in (try? await persistence.loadTasks(month: month)) ?? [] }
            }
            for await tasks in group { loaded.append(contentsOf: tasks) }
        }
        let loadedSeries = (try? await persistence.loadSeries()) ?? []

        for task in loaded { tasksByID[task.id] = task }
        for s in loadedSeries { series[s.id] = s }
        loadedMonths.formUnion(window)
        loadedMonths.insert(current)
        rebuildIndex()
        isLoaded = true
        materializeRecurrences(now: now)
        revision &+= 1
        onChange?(StoreChange(kind: .reload, taskIDs: []))
        let waiters = loadWaiters
        loadWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    /// Suspends until `bootstrap` has finished (used by intents/notification actions that may
    /// run right after a cold background launch).
    public func waitUntilLoaded() async {
        if isLoaded { return }
        await withCheckedContinuation { loadWaiters.append($0) }
    }

    /// Makes sure every month overlapping `interval` is in memory.
    public func ensureLoaded(_ interval: DateInterval) async {
        var month = MonthKey(interval.start, calendar: calendar)
        let last = MonthKey(interval.end, calendar: calendar)
        var missing: [MonthKey] = []
        while month <= last {
            if !loadedMonths.contains(month) { missing.append(month) }
            month = month.adding(months: 1)
        }
        guard !missing.isEmpty else { return }
        loadedMonths.formUnion(missing)
        var added: [PlanTask] = []
        for m in missing {
            added += (try? await persistence.loadTasks(month: m)) ?? []
        }
        guard !added.isEmpty else { return }
        for task in added where tasksByID[task.id] == nil {
            tasksByID[task.id] = task
            index(task)
        }
        revision &+= 1
    }

    // MARK: - Queries

    public func task(_ id: UUID) -> PlanTask? { tasksByID[id] }

    /// Tasks starting on `day`, chronologically. Cached per day until that day changes.
    public func tasks(on day: DayKey) -> [PlanTask] {
        if let cached = dayCache[day] { return cached }
        let result = (idsByDay[day] ?? []).compactMap { tasksByID[$0] }.sorted(by: ScheduleEngine.chronological)
        dayCache[day] = result
        return result
    }

    /// Tasks overlapping `interval`.
    public func tasks(in interval: DateInterval) -> [PlanTask] {
        // Include the previous day so blocks crossing midnight are found.
        var day = DayKey(interval.start, calendar: calendar).adding(days: -1, calendar: calendar)
        let last = DayKey(interval.end, calendar: calendar)
        var result: [PlanTask] = []
        while day <= last {
            for task in tasks(on: day) where task.start < interval.end && task.expectedEnd(at: interval.start) > interval.start {
                result.append(task)
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    /// Yesterday … tomorrow — the slice the Home screen and notifications care about.
    public func tasksAround(_ now: Date) -> [PlanTask] {
        let today = DayKey(now, calendar: calendar)
        var result: [PlanTask] = []
        for offset in -1...1 { result += tasks(on: today.adding(days: offset, calendar: calendar)) }
        if let active = activeTask, !result.contains(where: { $0.id == active.id }) { result.append(active) }
        return result
    }

    public var activeTask: PlanTask? {
        tasksByID.values.first(where: { $0.status.isActive })
    }

    /// Upcoming open tasks within `days`, for notification planning and widgets.
    public func upcoming(from now: Date, days: Int) -> [PlanTask] {
        let today = DayKey(now, calendar: calendar)
        var result: [PlanTask] = []
        for offset in 0..<max(1, days) {
            result += tasks(on: today.adding(days: offset, calendar: calendar)).filter { $0.status == .planned && $0.start > now }
        }
        return result
    }

    public func snapshot(at now: Date) -> NowSnapshot {
        ScheduleEngine.snapshot(tasks: tasksAround(now), now: now, calendar: calendar)
    }

    // MARK: - Editing

    @discardableResult
    public func add(_ task: PlanTask) -> PlanTask {
        var t = task
        t.updatedAt = Date()
        commit(upserts: [t], deletions: [], kind: .schedule)
        return t
    }

    public func update(_ task: PlanTask) {
        guard tasksByID[task.id] != nil else {
            add(task)
            return
        }
        var t = task
        t.updatedAt = Date()
        commit(upserts: [t], deletions: [], kind: .schedule)
    }

    /// Deletes a task. A recurring occurrence is excluded from its series so it never returns.
    @discardableResult
    public func delete(_ id: UUID, undoLabel: String? = "Deleted") -> PlanTask? {
        guard let existing = tasksByID[id] else { return nil }
        if let seriesID = existing.seriesID, let day = existing.occurrenceDay, var s = series[seriesID] {
            s.excludedDays.insert(day)
            series[seriesID] = s
            seriesDirty = true
        }
        if let undoLabel {
            pushUndo(label: undoLabel, inverse: ChangeSet(label: undoLabel, upserts: [existing]))
        }
        commit(upserts: [], deletions: [id], kind: .schedule)
        return existing
    }

    /// Applies a change set atomically and records its inverse for Undo.
    @discardableResult
    public func apply(_ changes: ChangeSet, now: Date = Date(), recordUndo: Bool = true) -> ChangeSet {
        var inverseUpserts: [PlanTask] = []
        var inverseDeletions: [UUID] = []
        var upserts: [PlanTask] = []
        for var task in changes.upserts {
            if let old = tasksByID[task.id] { inverseUpserts.append(old) } else { inverseDeletions.append(task.id) }
            task.updatedAt = now
            upserts.append(task)
        }
        var deletions: [UUID] = []
        for id in changes.deletions {
            guard let old = tasksByID[id] else { continue }
            inverseUpserts.append(old)
            deletions.append(id)
        }
        let inverse = ChangeSet(label: changes.label, upserts: inverseUpserts, deletions: inverseDeletions)
        if recordUndo, !changes.isEmpty { pushUndo(label: changes.label, inverse: inverse) }
        commit(upserts: upserts, deletions: deletions, kind: .schedule)
        return inverse
    }

    /// Reverts the most recent undoable change. Returns its label.
    @discardableResult
    public func undo(now: Date = Date()) -> String? {
        guard let entry = undoStack.popLast() else { return nil }
        apply(entry.inverse, now: now, recordUndo: false)
        return entry.label
    }

    public func undo(_ entryID: UUID, now: Date = Date()) {
        guard let index = undoStack.firstIndex(where: { $0.id == entryID }) else { return }
        let entry = undoStack.remove(at: index)
        apply(entry.inverse, now: now, recordUndo: false)
    }

    /// "I'm running late": shift every open task from `from` onwards by `minutes`.
    @discardableResult
    public func shiftRemaining(from: Date, byMinutes minutes: Int, now: Date = Date()) -> Int {
        let day = DayKey(from, calendar: calendar)
        let candidates = tasks(on: day)
        let shifted = ScheduleMath.shift(candidates, startingAtOrAfter: from, byMinutes: minutes, now: now)
        guard !shifted.isEmpty else { return 0 }
        apply(ChangeSet(label: "Shifted \(shifted.count) tasks by \(minutes)m", upserts: shifted), now: now)
        return shifted.count
    }

    // MARK: - Timer actions

    /// Performs a lifecycle action. Starting while another task is active throws
    /// `TransitionError.anotherTaskActive` unless `resolving` says what to do with it.
    @discardableResult
    public func perform(_ action: TaskAction, on id: UUID, at now: Date = Date(), resolving: ActiveConflictResolution? = nil) throws -> PlanTask {
        guard let task = tasksByID[id] else { throw TransitionError.notAllowed(from: .planned, action: "missing task") }
        var upserts: [PlanTask] = []
        if action == .start, let other = activeTask, other.id != id {
            guard let resolving else { throw TransitionError.anotherTaskActive(other.id) }
            let otherAction: TaskAction = resolving == .completeOther ? .complete : .cancel
            upserts.append(try TaskTransitions.apply(otherAction, to: other, at: now))
        }
        let updated = try TaskTransitions.apply(action, to: task, at: now)
        upserts.append(updated)
        if action == .skip || action == .cancel {
            let label = action == .skip ? "Skipped \(task.title)" : "Cancelled \(task.title)"
            pushUndo(label: label, inverse: ChangeSet(label: label, upserts: [task]))
        }
        commit(upserts: upserts, deletions: [], kind: .timer(action))
        return updated
    }

    /// Called when a running timer reaches zero and auto-complete is on.
    public func autoCompleteIfNeeded(now: Date, enabled: Bool) {
        guard enabled, let active = activeTask, active.status == .running,
              let session = active.session, session.isOverrun(at: now) else { return }
        let endAt = session.projectedEnd(at: now)
        _ = try? perform(.complete, on: active.id, at: endAt)
    }

    // MARK: - Recurring series

    public func addSeries(_ newSeries: TaskSeries, now: Date = Date()) {
        series[newSeries.id] = newSeries
        seriesDirty = true
        materializedThrough = nil
        materializeRecurrences(now: now)
        scheduleFlush()
    }

    /// Edits a series and every *future, not yet started* occurrence.
    public func updateSeries(_ updated: TaskSeries, now: Date = Date()) {
        series[updated.id] = updated
        seriesDirty = true
        let future = tasksByID.values.filter { $0.seriesID == updated.id && $0.status == .planned && $0.start > now }
        let deletions = future.map(\.id)
        commit(upserts: [], deletions: deletions, kind: .schedule)
        materializedThrough = nil
        materializeRecurrences(now: now)
    }

    /// Ends a series. Future unstarted occurrences are removed; history stays.
    public func endSeries(_ id: UUID, now: Date = Date()) {
        guard var s = series[id] else { return }
        s.lastDay = DayKey(now, calendar: calendar)
        series[id] = s
        seriesDirty = true
        let future = tasksByID.values.filter { $0.seriesID == id && $0.status == .planned && $0.start > now }
        commit(upserts: [], deletions: future.map(\.id), kind: .schedule)
    }

    /// Deletes a series and its not-yet-started occurrences (used to undo an assistant routine).
    public func removeSeries(_ id: UUID) {
        guard series.removeValue(forKey: id) != nil else { return }
        seriesDirty = true
        let planned = tasksByID.values.filter { $0.seriesID == id && $0.status == .planned }
        if planned.isEmpty {
            revision &+= 1
            scheduleFlush()
        } else {
            commit(upserts: [], deletions: planned.map(\.id), kind: .schedule)
        }
    }

    /// Creates concrete occurrences for the rolling window. Idempotent and cheap to call on
    /// every launch / day change.
    public func materializeRecurrences(now: Date = Date()) {
        guard !series.isEmpty else { return }
        let today = DayKey(now, calendar: calendar)
        let lastDay = today.adding(days: recurrenceWindowDays - 1, calendar: calendar)
        if let through = materializedThrough, through >= lastDay { return }
        let days = (0..<recurrenceWindowDays).map { today.adding(days: $0, calendar: calendar) }
        var existing = Set<SeriesDay>()
        for task in tasksByID.values {
            if let sid = task.seriesID, let day = task.occurrenceDay { existing.insert(SeriesDay(seriesID: sid, day: day)) }
        }
        let created = RecurrenceExpander.occurrences(for: Array(series.values), days: days, existing: existing, calendar: calendar, now: now)
        materializedThrough = lastDay
        if !created.isEmpty { commit(upserts: created, deletions: [], kind: .schedule) }
    }

    // MARK: - Persistence

    public func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        await writeDirty()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        let delay = flushDelay
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.writeDirty()
        }
    }

    private func writeDirty() async {
        let months = dirtyMonths
        dirtyMonths.removeAll()
        let writeSeries = seriesDirty
        seriesDirty = false
        // Snapshot values on the main actor; encoding + IO happen in the persistence actor.
        var payload: [(MonthKey, [PlanTask])] = []
        for month in months {
            var ids = Set<UUID>()
            for (day, dayIDs) in idsByDay where day.monthKey == month { ids.formUnion(dayIDs) }
            payload.append((month, ids.compactMap { tasksByID[$0] }))
        }
        let seriesPayload = writeSeries ? Array(series.values) : nil
        for (month, tasks) in payload {
            try? await persistence.saveTasks(tasks, month: month)
        }
        if let seriesPayload { try? await persistence.saveSeries(seriesPayload) }
    }

    // MARK: - Internals

    private func commit(upserts: [PlanTask], deletions: [UUID], kind: StoreChange.Kind) {
        guard !upserts.isEmpty || !deletions.isEmpty else { return }
        var ids: [UUID] = []
        for id in deletions {
            if let old = tasksByID.removeValue(forKey: id) {
                unindex(old)
                dirtyMonths.insert(MonthKey(old.start, calendar: calendar))
                ids.append(id)
            }
        }
        for task in upserts {
            if let old = tasksByID[task.id] {
                unindex(old)
                dirtyMonths.insert(MonthKey(old.start, calendar: calendar))
            }
            tasksByID[task.id] = task
            index(task)
            dirtyMonths.insert(MonthKey(task.start, calendar: calendar))
            ids.append(task.id)
        }
        revision &+= 1
        scheduleFlush()
        onChange?(StoreChange(kind: kind, taskIDs: ids))
    }

    private func index(_ task: PlanTask) {
        let day = DayKey(task.start, calendar: calendar)
        idsByDay[day, default: []].insert(task.id)
        dayCache[day] = nil
    }

    private func unindex(_ task: PlanTask) {
        let day = DayKey(task.start, calendar: calendar)
        idsByDay[day]?.remove(task.id)
        dayCache[day] = nil
    }

    /// Rebuild day buckets (after load or a time-zone change).
    public func rebuildIndex() {
        idsByDay.removeAll(keepingCapacity: true)
        dayCache.removeAll(keepingCapacity: true)
        for task in tasksByID.values {
            idsByDay[DayKey(task.start, calendar: calendar), default: []].insert(task.id)
        }
    }

    private func pushUndo(label: String, inverse: ChangeSet) {
        undoStack.append(UndoEntry(label: label, date: Date(), inverse: inverse))
        if undoStack.count > 20 { undoStack.removeFirst(undoStack.count - 20) }
    }
}
