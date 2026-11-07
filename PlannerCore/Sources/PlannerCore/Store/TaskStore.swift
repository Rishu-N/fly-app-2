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
///   O(tasks that day), not O(all tasks). The active task is tracked by id (O(1)).
/// - Writes mark only the touched *storage* month dirty and are flushed after a short debounce
///   on the persistence actor (off the main thread), serially, so a newer payload can never be
///   overtaken by an older one.
/// - Storage partitions use UTC months (never the device time zone), so travelling can't move a
///   task between files. The *display* day index uses the user's calendar.
/// - Older months are loaded lazily the first time a view asks for them; a month is only ever
///   written after it was read (read-merge-write otherwise), so partial data never overwrites disk.
@MainActor
@Observable
public final class TaskStore {
    public private(set) var tasksByID: [UUID: PlanTask] = [:]
    public private(set) var series: [UUID: TaskSeries] = [:]
    public private(set) var isLoaded = false
    /// Bumped on every mutation — every query reads it so views always register a dependency.
    public private(set) var revision = 0
    public private(set) var undoStack: [UndoEntry] = []
    public private(set) var activeTaskID: UUID?
    /// Months whose file could not be read; they are never written (data stays on disk untouched).
    public private(set) var unreadableMonths: Set<MonthKey> = []

    @ObservationIgnored public private(set) var calendar: Calendar
    @ObservationIgnored public var onChange: (@MainActor (StoreChange) -> Void)?
    @ObservationIgnored public var flushDelay: Duration = .milliseconds(350)
    @ObservationIgnored public var recurrenceWindowDays = 14

    @ObservationIgnored private let persistence: PlannerPersistence
    @ObservationIgnored private var idsByDay: [DayKey: Set<UUID>] = [:]
    @ObservationIgnored private var dayByID: [UUID: DayKey] = [:]
    @ObservationIgnored private var dayCache: [DayKey: [PlanTask]] = [:]
    @ObservationIgnored private var loadedMonths: Set<MonthKey> = []
    @ObservationIgnored private var dirtyMonths: Set<MonthKey> = []
    @ObservationIgnored private var seriesDirty = false
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var writeChain: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var materializedThrough: DayKey?

    public init(persistence: PlannerPersistence, calendar: Calendar = .autoupdatingCurrent) {
        self.persistence = persistence
        self.calendar = Self.snapshot(of: calendar)
    }

    /// A fixed copy of a calendar (never `.autoupdatingCurrent`), so index keys are stable until
    /// `setCalendar` is called explicitly.
    private static func snapshot(of calendar: Calendar) -> Calendar {
        var c = Calendar(identifier: calendar.identifier)
        c.timeZone = calendar.timeZone
        c.locale = calendar.locale
        c.firstWeekday = calendar.firstWeekday
        return c
    }

    // MARK: - Loading

    /// Loads the working window (2 months back → all future months) and series, then
    /// materialises recurring occurrences. Memoised: concurrent callers share one load.
    public func bootstrap(now: Date = Date()) async {
        if let loadTask { return await loadTask.value }
        let task = Task { await self.load(now: now) }
        loadTask = task
        await task.value
    }

    /// Suspends until the initial load has finished (starting it if needed). Every background
    /// entry point (intent, notification action) awaits this before touching data.
    public func waitUntilLoaded() async {
        await bootstrap()
    }

    private func load(now: Date) async {
        let current = StoragePartition.month(of: now)
        let earliest = current.adding(months: -2)
        let months = (try? await persistence.availableMonths()) ?? []
        let window = months.filter { $0 >= earliest }
        var results: [(MonthKey, Result<[PlanTask], Error>)] = []
        await withTaskGroup(of: (MonthKey, Result<[PlanTask], Error>).self) { group in
            for month in window {
                group.addTask { [persistence] in
                    do { return (month, .success(try await persistence.loadTasks(month: month))) }
                    catch { return (month, .failure(error)) }
                }
            }
            for await r in group { results.append(r) }
        }
        let loadedSeries = (try? await persistence.loadSeries()) ?? []

        for (month, result) in results {
            switch result {
            case .success(let tasks):
                merge(loaded: tasks)
                loadedMonths.insert(month)
            case .failure:
                unreadableMonths.insert(month)
            }
        }
        loadedMonths.insert(current)
        for s in loadedSeries where series[s.id] == nil { series[s.id] = s }
        rebuildIndex()
        isLoaded = true
        materializeRecurrences(now: now)
        revision &+= 1
        onChange?(StoreChange(kind: .reload, taskIDs: []))
        if !dirtyMonths.isEmpty || seriesDirty { scheduleFlush() }
    }

    /// Inserts tasks read from disk. Anything already in memory (edited before the load
    /// finished) wins; duplicate ids across files keep the newest `updatedAt` and heal the files.
    private func merge(loaded tasks: [PlanTask]) {
        for task in tasks {
            if let existing = tasksByID[task.id] {
                // Newest wins: covers both "edited in memory before the load finished" and
                // "the same task found in two files".
                if task.updatedAt > existing.updatedAt { tasksByID[task.id] = task }
                // A duplicate means two files hold the task: rewrite both.
                dirtyMonths.insert(StoragePartition.month(of: task.start))
                dirtyMonths.insert(StoragePartition.month(of: existing.start))
            } else {
                tasksByID[task.id] = task
            }
        }
    }

    /// Makes sure every month overlapping `interval` is in memory.
    public func ensureLoaded(_ interval: DateInterval) async {
        await waitUntilLoaded()
        var month = StoragePartition.month(of: interval.start)
        let last = StoragePartition.month(of: interval.end)
        var missing: [MonthKey] = []
        while month <= last {
            if !loadedMonths.contains(month), !unreadableMonths.contains(month) { missing.append(month) }
            month = month.adding(months: 1)
        }
        guard !missing.isEmpty else { return }
        var added = false
        for m in missing {
            do {
                let tasks = try await persistence.loadTasks(month: m)
                guard !loadedMonths.contains(m) else { continue }
                let before = tasksByID.count
                merge(loaded: tasks)
                loadedMonths.insert(m)
                added = added || tasksByID.count != before
            } catch {
                unreadableMonths.insert(m)
            }
        }
        if added {
            rebuildIndex()
            revision &+= 1
        }
    }

    // MARK: - Queries

    public func task(_ id: UUID) -> PlanTask? { tasksByID[id] }

    /// Tasks starting on `day`, chronologically. Cached per day until that day changes.
    public func tasks(on day: DayKey) -> [PlanTask] {
        _ = revision // register an observation dependency even when served from the cache
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
        activeTaskID.flatMap { tasksByID[$0] }
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

    /// Switch to a new calendar / time zone (e.g. after `NSSystemTimeZoneDidChange`). Task
    /// instants never change; only the display index is rebuilt.
    public func setCalendar(_ newCalendar: Calendar) {
        calendar = Self.snapshot(of: newCalendar)
        rebuildIndex()
        materializedThrough = nil
        materializeRecurrences()
        revision &+= 1
        onChange?(StoreChange(kind: .reload, taskIDs: []))
    }

    // MARK: - Editing (plan fields only — never clobbers a live timer)

    @discardableResult
    public func add(_ task: PlanTask) -> PlanTask {
        var t = task
        if tasksByID[t.id] == nil, t.source == .assistant || t.source == .quickAdd {
            t.status = .planned
            t.session = nil
        }
        t.updatedAt = Date()
        commit(upserts: [t], deletions: [], kind: .schedule)
        return t
    }

    /// Saves plan edits. Status and timer session always come from the current record, so an
    /// edit sheet that was open while the timer was paused from the Lock Screen can't undo that.
    public func update(_ task: PlanTask) {
        guard let current = tasksByID[task.id] else {
            add(task)
            return
        }
        var t = current.withPlanFields(from: task)
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
            pushUndo(label: undoLabel, inverse: ChangeSet(label: undoLabel, upserts: [existing], mode: .full))
        }
        commit(upserts: [], deletions: [id], kind: .schedule)
        return existing
    }

    /// Applies a change set atomically and records its inverse for Undo. In `.plan` mode,
    /// upserts of existing tasks only change plan fields (title, time, duration, …).
    @discardableResult
    public func apply(_ changes: ChangeSet, now: Date = Date(), recordUndo: Bool = true) -> ChangeSet {
        var inverseUpserts: [PlanTask] = []
        var inverseDeletions: [UUID] = []
        var upserts: [PlanTask] = []
        for task in changes.upserts {
            var t: PlanTask
            if let old = tasksByID[task.id] {
                inverseUpserts.append(old)
                t = changes.mode == .plan ? old.withPlanFields(from: task) : task
            } else {
                inverseDeletions.append(task.id)
                t = task
            }
            t.updatedAt = now
            upserts.append(t)
        }
        var deletions: [UUID] = []
        for id in changes.deletions {
            guard let old = tasksByID[id] else { continue }
            inverseUpserts.append(old)
            deletions.append(id)
        }
        let inverse = ChangeSet(label: changes.label, upserts: inverseUpserts, deletions: inverseDeletions, mode: changes.mode)
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

    /// Reverts a specific change (toasts hold the id of *their* change, so a background action in
    /// between can't make Undo revert the wrong thing).
    @discardableResult
    public func undo(_ entryID: UUID, now: Date = Date()) -> Bool {
        guard let index = undoStack.firstIndex(where: { $0.id == entryID }) else { return false }
        let entry = undoStack.remove(at: index)
        apply(entry.inverse, now: now, recordUndo: false)
        return true
    }

    /// Id of the most recently recorded undo entry.
    public var lastUndoID: UUID? { undoStack.last?.id }

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
    /// Complete / cancel / skip (and a resolved conflict) record one undo entry.
    @discardableResult
    public func perform(_ action: TaskAction, on id: UUID, at now: Date = Date(), resolving: ActiveConflictResolution? = nil) throws -> PlanTask {
        guard let task = tasksByID[id] else { throw TransitionError.notAllowed(from: .planned, action: "missing task") }
        var upserts: [PlanTask] = []
        var previous: [PlanTask] = []
        if action == .start, let other = activeTask, other.id != id {
            guard let resolving else { throw TransitionError.anotherTaskActive(other.id) }
            let otherAction: TaskAction = resolving == .completeOther ? .complete : .cancel
            upserts.append(try TaskTransitions.apply(otherAction, to: other, at: now))
            previous.append(other)
        }
        let updated = try TaskTransitions.apply(action, to: task, at: now)
        upserts.append(updated)
        previous.append(task)
        let label: String? = switch action {
        case .complete: "Completed \(task.title)"
        case .cancel: "Cancelled \(task.title)"
        case .skip: "Skipped \(task.title)"
        case .start where previous.count > 1: "Started \(task.title)"
        default: nil
        }
        if let label {
            pushUndo(label: label, inverse: ChangeSet(label: label, upserts: previous, mode: .full))
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

    /// Edits a series and patches every *future, not yet started* occurrence in place (same ids,
    /// so reminders and widgets only change where something actually changed).
    public func updateSeries(_ updated: TaskSeries, now: Date = Date()) {
        series[updated.id] = updated
        seriesDirty = true
        var upserts: [PlanTask] = []
        var deletions: [UUID] = []
        for task in tasksByID.values where task.seriesID == updated.id && task.status == .planned && task.start > now {
            guard let day = task.occurrenceDay, updated.occurs(on: day, calendar: calendar) else {
                deletions.append(task.id)
                continue
            }
            var fresh = updated.makeOccurrence(on: day, calendar: calendar, now: now)
            fresh.createdAt = task.createdAt
            fresh.checklist = task.checklist.count == updated.checklistTitles.count ? task.checklist : fresh.checklist
            upserts.append(fresh)
        }
        if !upserts.isEmpty || !deletions.isEmpty {
            apply(ChangeSet(label: "Edited routine \(updated.title)", upserts: upserts, deletions: deletions), now: now)
        }
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
        guard isLoaded, !series.isEmpty else { return }
        let today = DayKey(now, calendar: calendar)
        let lastDay = today.adding(days: recurrenceWindowDays - 1, calendar: calendar)
        if let through = materializedThrough, through >= lastDay { return }
        let days = (0..<recurrenceWindowDays).map { today.adding(days: $0, calendar: calendar) }
        var existing = Set<SeriesDay>()
        for task in tasksByID.values {
            if let sid = task.seriesID, let day = task.occurrenceDay { existing.insert(SeriesDay(seriesID: sid, day: day)) }
        }
        let created = RecurrenceExpander.occurrences(for: Array(series.values), days: days, existing: existing, calendar: calendar, now: now)
            .filter { tasksByID[$0.id] == nil }
        materializedThrough = lastDay
        if !created.isEmpty { commit(upserts: created, deletions: [], kind: .schedule) }
    }

    // MARK: - Persistence

    /// Writes everything dirty and waits for all in-flight writes to land.
    public func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        enqueueWrite()
        await writeChain?.value
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        let delay = flushDelay
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.enqueueWrite()
        }
    }

    /// Appends one write to the serial chain. The payload is captured now (on the main actor);
    /// encoding + IO happen in the persistence actor.
    private func enqueueWrite() {
        guard isLoaded, !dirtyMonths.isEmpty || seriesDirty else { return }
        let months = dirtyMonths.subtracting(unreadableMonths)
        dirtyMonths.removeAll()
        let writeSeries = seriesDirty
        seriesDirty = false

        var payload: [(month: MonthKey, tasks: [PlanTask], needsMerge: Bool)] = []
        for month in months {
            let tasks = tasksByID.values.filter { StoragePartition.month(of: $0.start) == month }
            payload.append((month, tasks, !loadedMonths.contains(month)))
        }
        let seriesPayload = writeSeries ? Array(series.values) : nil
        let previous = writeChain
        let persistence = self.persistence
        writeChain = Task { [weak self] in
            await previous?.value
            var failed: [MonthKey] = []
            var mergedIn: [MonthKey: [PlanTask]] = [:]
            for item in payload {
                do {
                    var tasks = item.tasks
                    if item.needsMerge {
                        // Never overwrite a month we haven't read: merge with what's on disk.
                        let onDisk = try await persistence.loadTasks(month: item.month)
                        let ids = Set(tasks.map(\.id))
                        let extra = onDisk.filter { !ids.contains($0.id) }
                        tasks += extra
                        mergedIn[item.month] = extra
                    }
                    try await persistence.saveTasks(tasks, month: item.month)
                } catch {
                    failed.append(item.month)
                }
            }
            var seriesFailed = false
            if let seriesPayload {
                do { try await persistence.saveSeries(seriesPayload) } catch { seriesFailed = true }
            }
            await MainActor.run {
                guard let self else { return }
                for (month, extra) in mergedIn {
                    self.loadedMonths.insert(month)
                    self.merge(loaded: extra)
                    for t in extra {
                        if let current = self.tasksByID[t.id] {
                            self.unindex(t.id)
                            self.index(current)
                        }
                    }
                }
                if !mergedIn.isEmpty { self.revision &+= 1 }
                if !failed.isEmpty || seriesFailed {
                    self.dirtyMonths.formUnion(failed)
                    if seriesFailed { self.seriesDirty = true }
                }
            }
        }
    }

    // MARK: - Internals

    private func commit(upserts: [PlanTask], deletions: [UUID], kind: StoreChange.Kind) {
        guard !upserts.isEmpty || !deletions.isEmpty else { return }
        var ids: [UUID] = []
        for id in deletions {
            if let old = tasksByID.removeValue(forKey: id) {
                unindex(old.id)
                dirtyMonths.insert(StoragePartition.month(of: old.start))
                if activeTaskID == id { activeTaskID = nil }
                ids.append(id)
            }
        }
        for task in upserts {
            if let old = tasksByID[task.id] {
                unindex(old.id)
                dirtyMonths.insert(StoragePartition.month(of: old.start))
            }
            tasksByID[task.id] = task
            index(task)
            dirtyMonths.insert(StoragePartition.month(of: task.start))
            if task.status.isActive {
                activeTaskID = task.id
            } else if activeTaskID == task.id {
                activeTaskID = nil
            }
            ids.append(task.id)
        }
        revision &+= 1
        scheduleFlush()
        onChange?(StoreChange(kind: kind, taskIDs: ids))
    }

    private func index(_ task: PlanTask) {
        let day = DayKey(task.start, calendar: calendar)
        idsByDay[day, default: []].insert(task.id)
        dayByID[task.id] = day
        dayCache[day] = nil
    }

    /// Unindexes by the *stored* key, so it's correct even if the calendar changed.
    private func unindex(_ id: UUID) {
        guard let day = dayByID.removeValue(forKey: id) else { return }
        idsByDay[day]?.remove(id)
        dayCache[day] = nil
    }

    /// Rebuild day buckets (after load or a time-zone change).
    private func rebuildIndex() {
        idsByDay.removeAll(keepingCapacity: true)
        dayByID.removeAll(keepingCapacity: true)
        dayCache.removeAll(keepingCapacity: true)
        activeTaskID = nil
        for task in tasksByID.values {
            let day = DayKey(task.start, calendar: calendar)
            idsByDay[day, default: []].insert(task.id)
            dayByID[task.id] = day
            if task.status.isActive {
                // Invariant: at most one active task. If files disagree, keep the most recent.
                if let current = activeTaskID, let other = tasksByID[current], other.updatedAt > task.updatedAt { continue }
                activeTaskID = task.id
            }
        }
    }

    private func pushUndo(label: String, inverse: ChangeSet) {
        undoStack.append(UndoEntry(label: label, date: Date(), inverse: inverse))
        if undoStack.count > 20 { undoStack.removeFirst(undoStack.count - 20) }
    }
}

/// Storage partition: the UTC month of a task's planned start. Independent of the device time
/// zone by design.
public enum StoragePartition {
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    public static func month(of date: Date) -> MonthKey {
        MonthKey(date, calendar: utc)
    }
}

extension PlanTask {
    /// This task's execution state (status, timer, provenance) with `other`'s plan fields.
    public func withPlanFields(from other: PlanTask) -> PlanTask {
        var t = self
        t.title = other.title
        t.notes = other.notes
        t.start = other.start
        t.durationMinutes = other.durationMinutes
        t.category = other.category
        t.leadTimeMinutes = other.leadTimeMinutes
        t.remind = other.remind
        t.checklist = other.checklist
        return t
    }
}
