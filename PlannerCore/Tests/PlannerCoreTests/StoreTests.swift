import XCTest
@testable import PlannerCore

@MainActor
final class StoreTests: XCTestCase {
    func testDayQueriesAndIndexMaintenance() async {
        let a = task("A", 9), b = task("B", 11), c = task("C", 10, day: 8)
        let (store, _) = await makeStore([a, b, c])
        XCTAssertEqual(store.tasks(on: DayKey(year: 2026, month: 11, day: 7)).map(\.title), ["A", "B"])
        var moved = b
        moved.start = TestClock.at(9, day: 8)
        store.update(moved)
        XCTAssertEqual(store.tasks(on: DayKey(year: 2026, month: 11, day: 7)).map(\.title), ["A"])
        XCTAssertEqual(store.tasks(on: DayKey(year: 2026, month: 11, day: 8)).map(\.title), ["B", "C"])
    }

    func testSingleActiveRule() async throws {
        let a = task("A", 9), b = task("B", 10)
        let (store, _) = await makeStore([a, b])
        try store.perform(.start, on: a.id, at: TestClock.at(9))
        XCTAssertThrowsError(try store.perform(.start, on: b.id, at: TestClock.at(9, 30))) { error in
            XCTAssertEqual(error as? TransitionError, .anotherTaskActive(a.id))
        }
        try store.perform(.start, on: b.id, at: TestClock.at(9, 30), resolving: .completeOther)
        XCTAssertEqual(store.task(a.id)?.status, .completed)
        XCTAssertEqual(store.activeTask?.id, b.id)
    }

    func testChangeSetUndo() async {
        let a = task("A", 9), b = task("B", 10)
        let (store, _) = await makeStore([a, b])
        var moved = a
        moved.start = TestClock.at(15)
        let added = task("New", 17)
        store.apply(ChangeSet(label: "AI", upserts: [moved, added], deletions: [b.id]))
        XCTAssertEqual(store.task(a.id)?.start, TestClock.at(15))
        XCTAssertNil(store.task(b.id))
        XCTAssertNotNil(store.task(added.id))
        XCTAssertEqual(store.undo(), "AI")
        XCTAssertEqual(store.task(a.id)?.start, TestClock.at(9))
        XCTAssertNotNil(store.task(b.id))
        XCTAssertNil(store.task(added.id))
    }

    func testShiftRemaining() async throws {
        let a = task("A", 9), b = task("B", 10), c = task("C", 11)
        let (store, _) = await makeStore([a, b, c])
        try store.perform(.start, on: a.id, at: TestClock.at(9, 20))
        XCTAssertEqual(store.shiftRemaining(from: TestClock.at(10), byMinutes: 20), 2)
        XCTAssertEqual(store.task(b.id)?.start, TestClock.at(10, 20))
        XCTAssertEqual(store.task(c.id)?.start, TestClock.at(11, 20))
        XCTAssertEqual(store.task(a.id)?.start, TestClock.at(9))
    }

    func testRecurringSeriesMaterialisesAndExcludesDeletedDay() async {
        let (store, _) = await makeStore([], now: TestClock.at(8))
        let series = TaskSeries(title: "Walk", category: .health, durationMinutes: 20, hour: 7, minute: 0,
                                rule: .daily, firstDay: DayKey(year: 2026, month: 11, day: 7))
        store.addSeries(series, now: TestClock.at(8))
        let nov8 = DayKey(year: 2026, month: 11, day: 8)
        XCTAssertEqual(store.tasks(on: nov8).count, 1)
        XCTAssertEqual(store.tasksByID.values.filter { $0.seriesID == series.id }.count, store.recurrenceWindowDays)
        let occurrence = store.tasks(on: nov8)[0]
        store.delete(occurrence.id)
        XCTAssertTrue(store.tasks(on: nov8).isEmpty)
        store.materializeRecurrences(now: TestClock.at(8))
        XCTAssertTrue(store.tasks(on: nov8).isEmpty)
        XCTAssertTrue(store.series[series.id]!.excludedDays.contains(nov8))
    }

    func testJSONPersistenceRoundTripOnlyWritesDirtyMonth() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("planner-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = JSONFilePersistence(directory: dir)
        let store = TaskStore(persistence: persistence, calendar: TestClock.calendar)
        await store.bootstrap(now: TestClock.at(9))
        var a = task("Nov task", 9)
        a.notes = "notes survive"
        a.checklist = [ChecklistItem(title: "step")]
        store.add(a)
        store.add(PlanTask(title: "Dec task", start: TestClock.at(9, day: 2, month: 12), durationMinutes: 30))
        try store.perform(.start, on: a.id, at: TestClock.at(9, 1))
        await store.flushNow()

        let months = try await persistence.availableMonths()
        XCTAssertEqual(months.map(\.description), ["2026-11", "2026-12"])

        let reloaded = TaskStore(persistence: JSONFilePersistence(directory: dir), calendar: TestClock.calendar)
        await reloaded.bootstrap(now: TestClock.at(9))
        let restored = try XCTUnwrap(reloaded.task(a.id))
        XCTAssertEqual(restored.notes, "notes survive")
        XCTAssertEqual(restored.status, .running)
        XCTAssertEqual(restored.session?.startedAt, TestClock.at(9, 1))
        XCTAssertEqual(restored.checklist.first?.title, "step")
        XCTAssertEqual(reloaded.tasksByID.count, 2)
    }

    func testDecodingToleratesMissingFields() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","start":1794042000,"title":"Old"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let t = try decoder.decode(PlanTask.self, from: Data(json.utf8))
        XCTAssertEqual(t.durationMinutes, 30)
        XCTAssertEqual(t.status, .planned)
        XCTAssertTrue(t.remind)
    }

    func testOnChangeReportsTimerActions() async throws {
        let a = task("A", 9)
        let (store, _) = await makeStore([a])
        var kinds: [StoreChange.Kind] = []
        store.onChange = { kinds.append($0.kind) }
        try store.perform(.start, on: a.id, at: TestClock.at(9))
        try store.perform(.pause, on: a.id, at: TestClock.at(9, 5))
        XCTAssertEqual(kinds, [.timer(.start), .timer(.pause)])
    }
}
