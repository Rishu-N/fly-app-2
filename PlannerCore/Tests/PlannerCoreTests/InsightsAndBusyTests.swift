import XCTest
@testable import PlannerCore

final class InsightsTests: XCTestCase {
    func testDayInsights() throws {
        var done = try TaskTransitions.apply(.start, to: task("Write", 9, 0, minutes: 60), at: TestClock.at(9, 3))
        done = try TaskTransitions.apply(.complete, to: done, at: TestClock.at(10, 13)) // 70 min, 10 over
        var late = try TaskTransitions.apply(.start, to: task("Email", 10, 0, minutes: 30, category: .admin), at: TestClock.at(10, 20))
        late = try TaskTransitions.apply(.cancel, to: late, at: TestClock.at(10, 30))
        let skipped = task("Gym", 12, status: .skipped, category: .health)
        let missed = task("Read", 8, 0, minutes: 15, category: .learning)
        let d = InsightsEngine.day(DayKey(year: 2026, month: 11, day: 7), tasks: [done, late, skipped, missed], now: TestClock.at(13))
        XCTAssertEqual(d.total, 4)
        XCTAssertEqual(d.completed, 1)
        XCTAssertEqual(d.cancelled, 1)
        XCTAssertEqual(d.skipped, 1)
        XCTAssertEqual(d.missed, 1)
        XCTAssertEqual(d.startedCount, 2)
        XCTAssertEqual(d.onTimeStarts, 1)             // 3 min late = on time; 20 min late = not
        XCTAssertEqual(d.focusedMinutes, 80)          // 70 + 10
        XCTAssertEqual(d.overrunMinutes, 10)
        XCTAssertEqual(d.focusedMinutesByCategory[.focus], 70)
        XCTAssertEqual(d.focusedMinutesByCategory[.admin], 10)
        XCTAssertEqual(d.averageStartDriftMinutes, 11.5, accuracy: 0.01)
        XCTAssertEqual(d.completionRate, 0.25, accuracy: 0.001)
    }

    func testRangeAndStreak() throws {
        let cal = TestClock.calendar
        var byDay: [DayKey: [PlanTask]] = [:]
        for dayNumber in 4...6 {
            var t = try TaskTransitions.apply(.start, to: task("Focus", 9, day: dayNumber), at: TestClock.at(9, day: dayNumber))
            t = try TaskTransitions.apply(.complete, to: t, at: TestClock.at(9, 50, day: dayNumber))
            byDay[DayKey(year: 2026, month: 11, day: dayNumber)] = [t]
        }
        // Today (7th) has nothing done yet → streak counts from yesterday.
        byDay[DayKey(year: 2026, month: 11, day: 7)] = [task("Later", 15)]
        let r = InsightsEngine.range(endingOn: DayKey(year: 2026, month: 11, day: 7), days: 7, calendar: cal, now: TestClock.at(10)) {
            byDay[$0] ?? []
        }
        XCTAssertEqual(r.days.count, 7)
        XCTAssertEqual(r.days.last?.day, DayKey(year: 2026, month: 11, day: 7))
        XCTAssertEqual(r.streak, 3)
        XCTAssertEqual(r.focusedMinutes, 150)
        XCTAssertEqual(r.topCategory, .focus)
    }
}

final class BusyBlockTests: XCTestCase {
    func testFreeSlotsAvoidCalendarEvents() {
        let tasks = [task("A", 9, 0, minutes: 60)]
        let busy = [
            BusyBlock(id: "e1", title: "Dentist", start: TestClock.at(11), end: TestClock.at(11, 30)),
            BusyBlock(id: "e2", title: "Holiday", start: TestClock.at(0), end: TestClock.at(0, day: 8), isAllDay: true),
        ]
        let window = DateInterval(start: TestClock.at(8), end: TestClock.at(13))
        let slots = ScheduleMath.freeSlots(in: window, tasks: tasks, busy: busy, minimumMinutes: 30)
        XCTAssertEqual(slots, [
            DateInterval(start: TestClock.at(8), end: TestClock.at(9)),
            DateInterval(start: TestClock.at(10), end: TestClock.at(11)),
            DateInterval(start: TestClock.at(11, 30), end: TestClock.at(13)),
        ])
        XCTAssertEqual(ScheduleMath.conflicts(tasks: [task("Clash", 11, 15, minutes: 30)], busy: busy).count, 1)
    }
}
