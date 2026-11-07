import Observation
import XCTest
@testable import PlannerCore

/// Regression tests for the tech-lead review (docs/ARCHITECTURE.md §11).
@MainActor
final class StoreRegressionTests: XCTestCase {
    /// P0-1: storage partition must not depend on the device time zone.
    func testTimeZoneChangeNeverDropsTasksFromDisk() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tz-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let edge = ny.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 23, minute: 30))!
        let other = ny.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9))!

        let store = TaskStore(persistence: JSONFilePersistence(directory: dir), calendar: ny)
        store.flushDelay = .milliseconds(1)
        await store.bootstrap(now: other)
        let a = store.add(PlanTask(title: "Edge", start: edge, durationMinutes: 30))
        let b = store.add(PlanTask(title: "Other", start: other, durationMinutes: 30))
        await store.flushNow()

        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        store.setCalendar(london)
        var edited = store.task(b.id)!
        edited.title = "Other (edited)"
        store.update(edited)
        await store.flushNow()

        let reloaded = TaskStore(persistence: JSONFilePersistence(directory: dir), calendar: london)
        await reloaded.bootstrap(now: other)
        XCTAssertNotNil(reloaded.task(a.id), "task near a month edge must survive a time-zone change")
        XCTAssertEqual(reloaded.task(b.id)?.title, "Other (edited)")
        XCTAssertEqual(reloaded.tasksByID.count, 2)
    }

    /// P0-2: a month that was never read is merged, not overwritten.
    func testWritingToUnloadedMonthMergesWithDisk() async throws {
        let old = task("Ancient", 9, day: 3, month: 5) // May — outside the 2-month load window
        let persistence = InMemoryPersistence(tasks: [old], calendar: TestClock.calendar)
        let store = TaskStore(persistence: persistence, calendar: TestClock.calendar)
        store.flushDelay = .milliseconds(1)
        await store.bootstrap(now: TestClock.at(9))
        XCTAssertNil(store.task(old.id))
        store.add(task("New in May", 10, day: 4, month: 5))
        await store.flushNow()
        let may = try await persistence.loadTasks(month: StoragePartition.month(of: old.start))
        XCTAssertEqual(Set(may.map(\.title)), ["Ancient", "New in May"])
    }

    /// P0-3: concurrent bootstrap calls share one load and don't clobber in-between edits.
    func testBootstrapIsMemoised() async throws {
        let a = task("A", 9)
        let persistence = InMemoryPersistence(tasks: [a], calendar: TestClock.calendar)
        let store = TaskStore(persistence: persistence, calendar: TestClock.calendar)
        await store.bootstrap(now: TestClock.at(9))
        try store.perform(.start, on: a.id, at: TestClock.at(9))
        await store.bootstrap(now: TestClock.at(9))
        await store.waitUntilLoaded()
        XCTAssertEqual(store.task(a.id)?.status, .running)
    }

    /// P0-4: reading a day from the cache must still register an observation dependency.
    func testDayQueryIsObservedEvenWhenCached() async {
        let (store, _) = await makeStore([task("A", 9)])
        let day = DayKey(year: 2026, month: 11, day: 7)
        _ = store.tasks(on: day) // warm the cache
        let fired = Flag()
        withObservationTracking {
            _ = store.tasks(on: day)
        } onChange: {
            fired.value = true
        }
        store.add(task("B", 10))
        XCTAssertTrue(fired.value)
    }

    /// P0-6: a stale copy saved from an edit sheet can't resurrect or kill a timer.
    func testPlanEditsNeverClobberTimerState() async throws {
        let a = task("A", 9)
        let (store, _) = await makeStore([a])
        let staleCopy = store.task(a.id)!           // edit sheet opened
        try store.perform(.start, on: a.id, at: TestClock.at(9))
        try store.perform(.pause, on: a.id, at: TestClock.at(9, 10)) // Lock Screen pause
        var edited = staleCopy
        edited.title = "A renamed"
        store.update(edited)                         // sheet saved
        let now = store.task(a.id)!
        XCTAssertEqual(now.title, "A renamed")
        XCTAssertEqual(now.status, .paused)
        XCTAssertNotNil(now.session?.pausedAt)
    }

    /// P1-10: undo of complete restores the running timer; toasts undo *their* entry.
    func testUndoCompleteAndUndoByID() async throws {
        let a = task("A", 9), b = task("B", 10)
        let (store, _) = await makeStore([a, b])
        try store.perform(.start, on: a.id, at: TestClock.at(9))
        try store.perform(.complete, on: a.id, at: TestClock.at(9, 30))
        let completeEntry = try XCTUnwrap(store.lastUndoID)
        try store.perform(.skip, on: b.id, at: TestClock.at(9, 31))
        XCTAssertTrue(store.undo(completeEntry))
        XCTAssertEqual(store.task(a.id)?.status, .running)
        XCTAssertEqual(store.task(b.id)?.status, .skipped, "undo by id must not revert the later skip")
        XCTAssertEqual(store.activeTask?.id, a.id)
    }

    /// P1-9: occurrences have deterministic ids and series edits patch them in place.
    func testSeriesEditPatchesOccurrencesInPlace() async {
        let (store, _) = await makeStore([], now: TestClock.at(6))
        var s = TaskSeries(title: "Walk", category: .health, durationMinutes: 20, hour: 7, minute: 0,
                           rule: .daily, firstDay: DayKey(year: 2026, month: 11, day: 7))
        store.addSeries(s, now: TestClock.at(6))
        let before = Set(store.tasksByID.keys)
        s.durationMinutes = 30
        store.updateSeries(s, now: TestClock.at(6))
        XCTAssertEqual(Set(store.tasksByID.keys), before)
        XCTAssertTrue(store.tasksByID.values.allSatisfy { $0.durationMinutes == 30 })
        XCTAssertEqual(StableHash.uuid("x/2026-11-07"), StableHash.uuid("x/2026-11-07"))
    }

    /// Assistant can never reset a task that started after the proposal was staged.
    func testAssistantApplySkipsTasksThatStarted() async throws {
        let a = task("Gym", 18)
        let (store, _) = await makeStore([a])
        var moved = a
        moved.start = TestClock.at(19)
        var proposal = Proposal(id: "cs_9", summary: "Move gym")
        proposal.items = [ProposalItem(kind: .move, before: a, after: moved)]
        try store.perform(.start, on: a.id, at: TestClock.at(17, 58))
        let result = ToolExecutor(store: store, settings: PlannerSettings(), now: TestClock.at(18), shareNotes: false).apply(proposal)
        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(result.skipped, ["Gym"])
        XCTAssertEqual(store.task(a.id)?.status, .running)
    }

    func testCorruptRecordIsDroppedNotTheMonth() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lossy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let good = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","start":1794042000,"title":"Good","durationMinutes":30,"createdAt":1794042000,"updatedAt":1794042000,"status":"planned","category":"focus"}"#
        let bad = #"{"title":"no id or start"}"#
        try Data(#"{"version":1,"tasks":[\#(good),\#(bad)]}"#.utf8).write(to: dir.appendingPathComponent("tasks-2026-11.json"))
        let tasks = try await JSONFilePersistence(directory: dir).loadTasks(month: MonthKey(year: 2026, month: 11))
        XCTAssertEqual(tasks.map(\.title), ["Good"])
    }
}

final class Flag: @unchecked Sendable { var value = false }
