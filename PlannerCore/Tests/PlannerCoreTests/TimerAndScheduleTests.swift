import XCTest
@testable import PlannerCore

final class TimerSessionTests: XCTestCase {
    /// The client's headline rule: 2:00–3:00 started at 1:58 → 60-minute timer ending 2:58.
    func testEarlyStartRunsFullPlannedDuration() throws {
        let t = task("Deep work", 14, 0, minutes: 60)
        let started = try TaskTransitions.apply(.start, to: t, at: TestClock.at(13, 58))
        XCTAssertEqual(started.status, .running)
        let end = try XCTUnwrap(started.session).projectedEnd(at: TestClock.at(14, 10))
        XCTAssertEqual(end, TestClock.at(14, 58))
        XCTAssertEqual(started.session!.remaining(at: TestClock.at(14, 28)), 30 * 60, accuracy: 0.001)
    }

    func testLateStartAlsoRunsFullDuration() throws {
        let t = task("Deep work", 14, 0, minutes: 60)
        let started = try TaskTransitions.apply(.start, to: t, at: TestClock.at(14, 10))
        XCTAssertEqual(started.session!.projectedEnd(at: TestClock.at(14, 10)), TestClock.at(15, 10))
    }

    func testPauseResumeShiftsEnd() throws {
        var t = try TaskTransitions.apply(.start, to: task("A", 10, 0, minutes: 30), at: TestClock.at(10, 0))
        t = try TaskTransitions.apply(.pause, to: t, at: TestClock.at(10, 10))
        // While paused, remaining is frozen at 20 minutes.
        XCTAssertEqual(t.session!.remaining(at: TestClock.at(10, 25)), 20 * 60, accuracy: 0.001)
        XCTAssertEqual(t.session!.projectedEnd(at: TestClock.at(10, 25)), TestClock.at(10, 45))
        t = try TaskTransitions.apply(.resume, to: t, at: TestClock.at(10, 25))
        XCTAssertEqual(t.session!.projectedEnd(at: TestClock.at(10, 30)), TestClock.at(10, 45))
        t = try TaskTransitions.apply(.complete, to: t, at: TestClock.at(10, 40))
        XCTAssertEqual(t.status, .completed)
        XCTAssertEqual(t.session!.elapsed(at: TestClock.at(12)), 25 * 60, accuracy: 0.001)
    }

    func testCompleteWhilePausedFoldsPause() throws {
        var t = try TaskTransitions.apply(.start, to: task("A", 10, 0, minutes: 30), at: TestClock.at(10, 0))
        t = try TaskTransitions.apply(.pause, to: t, at: TestClock.at(10, 5))
        t = try TaskTransitions.apply(.complete, to: t, at: TestClock.at(10, 20))
        XCTAssertEqual(t.session!.elapsed(at: TestClock.at(11)), 5 * 60, accuracy: 0.001)
        XCTAssertEqual(t.session!.pausedTotal, 15 * 60, accuracy: 0.001)
        XCTAssertNil(t.session!.pausedAt)
    }

    func testOverrunAndExtend() throws {
        var t = try TaskTransitions.apply(.start, to: task("A", 10, 0, minutes: 30), at: TestClock.at(10, 0))
        XCTAssertEqual(t.phase(at: TestClock.at(10, 35)), .overrun)
        XCTAssertEqual(t.session!.remaining(at: TestClock.at(10, 35)), -5 * 60, accuracy: 0.001)
        // In overtime, +10 means ten more minutes from now (not 10 off the 5-minute debt).
        t = try TaskTransitions.apply(.extend(minutes: 10), to: t, at: TestClock.at(10, 35))
        XCTAssertEqual(t.phase(at: TestClock.at(10, 35)), .running)
        XCTAssertEqual(t.session!.projectedEnd(at: TestClock.at(10, 35)), TestClock.at(10, 45))
        // Before zero it simply adds.
        var u = try TaskTransitions.apply(.start, to: task("B", 11, 0, minutes: 30), at: TestClock.at(11))
        u = try TaskTransitions.apply(.extend(minutes: 5), to: u, at: TestClock.at(11, 10))
        XCTAssertEqual(u.session!.projectedEnd(at: TestClock.at(11, 10)), TestClock.at(11, 35))
    }

    func testInvalidTransitionsThrow() {
        let t = task("A", 10)
        XCTAssertThrowsError(try TaskTransitions.apply(.pause, to: t, at: TestClock.at(10)))
        XCTAssertThrowsError(try TaskTransitions.apply(.resume, to: t, at: TestClock.at(10)))
    }

    func testFormatting() {
        XCTAssertEqual(formatClock(65), "1:05")
        XCTAssertEqual(formatClock(3725), "1:02:05")
        XCTAssertEqual(formatClock(-130), "+2:10")
        XCTAssertEqual(formatDuration(45), "45m")
        XCTAssertEqual(formatDuration(90), "1h 30m")
        XCTAssertEqual(formatDuration(120), "2h")
    }
}

final class NowSnapshotTests: XCTestCase {
    let cal = TestClock.calendar

    func testDueTaskBecomesFocusWithPreviousAndNextTwo() {
        let a = task("Email", 9, 0, minutes: 30, status: .completed)
        let b = task("Deep work", 9, 30, minutes: 60)
        let c = task("Lunch", 12, 0, minutes: 45)
        let d = task("Gym", 13, 0, minutes: 60)
        let e = task("Read", 15, 0, minutes: 30)
        let s = ScheduleEngine.snapshot(tasks: [e, d, c, b, a], now: TestClock.at(9, 40), calendar: cal)
        XCTAssertEqual(s.focus, .due(b))
        XCTAssertEqual(s.previous?.id, a.id)
        XCTAssertEqual(s.upcoming.map(\.id), [c.id, d.id])
    }

    func testActiveTaskIsNeverDisplaced() throws {
        let a = try TaskTransitions.apply(.start, to: task("Deep work", 9, 0, minutes: 60), at: TestClock.at(9, 5))
        let b = task("Call", 10, 0, minutes: 30)
        // At 10:10 the call's window has opened, but the overrunning task keeps the lens.
        let s = ScheduleEngine.snapshot(tasks: [a, b], now: TestClock.at(10, 10), calendar: cal)
        XCTAssertEqual(s.focusTask?.id, a.id)
        XCTAssertEqual(s.upcoming.first?.id, b.id)
        XCTAssertEqual(s.projectedLateMinutes, 10)
    }

    func testGapShowsNextTask() {
        let a = task("Done", 8, 0, minutes: 30, status: .completed)
        let b = task("Later", 11, 0, minutes: 30)
        let c = task("After", 12, 0, minutes: 30)
        let s = ScheduleEngine.snapshot(tasks: [a, b, c], now: TestClock.at(9), calendar: cal)
        XCTAssertEqual(s.focus, .gap(next: b))
        XCTAssertEqual(s.upcoming.map(\.id), [c.id])
        XCTAssertEqual(s.previous?.id, a.id)
    }

    func testMissedTaskCountsAndShowsAsPrevious() {
        let missed = task("Missed", 8, 0, minutes: 30)
        let s = ScheduleEngine.snapshot(tasks: [missed], now: TestClock.at(9), calendar: cal)
        XCTAssertEqual(s.focus, .clear)
        XCTAssertEqual(s.missedCount, 1)
        XCTAssertEqual(s.previous?.id, missed.id)
        XCTAssertEqual(missed.phase(at: TestClock.at(9)), .missed)
    }

    func testNextBoundary() throws {
        let a = task("A", 10, 0, minutes: 30)
        let running = try TaskTransitions.apply(.start, to: task("B", 9, 0, minutes: 30), at: TestClock.at(9, 2))
        XCTAssertEqual(ScheduleEngine.nextBoundary(after: TestClock.at(9, 10), tasks: [a, running]), TestClock.at(9, 32))
        XCTAssertEqual(ScheduleEngine.nextBoundary(after: TestClock.at(9, 40), tasks: [a, running]), TestClock.at(10))
    }

    func testFreeSlots() {
        let tasks = [task("A", 9, 0, minutes: 60), task("B", 11, 0, minutes: 30), task("Done", 13, 0, minutes: 60, status: .completed)]
        let window = DateInterval(start: TestClock.at(8), end: TestClock.at(14))
        let slots = ScheduleMath.freeSlots(in: window, tasks: tasks, minimumMinutes: 30)
        XCTAssertEqual(slots, [
            DateInterval(start: TestClock.at(8), end: TestClock.at(9)),
            DateInterval(start: TestClock.at(10), end: TestClock.at(11)),
            DateInterval(start: TestClock.at(11, 30), end: TestClock.at(14)),
        ])
    }

    func testOverlaps() {
        let pairs = ScheduleMath.overlaps([task("A", 9, 0, minutes: 60), task("B", 9, 30, minutes: 30), task("C", 10, 0, minutes: 30)])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.1.title, "B")
    }
}

final class RecurrenceTests: XCTestCase {
    func testWeekdaysRule() {
        let cal = TestClock.calendar
        let series = TaskSeries(title: "Standup", category: .meeting, durationMinutes: 15, hour: 9, minute: 30,
                                rule: .weekdays, firstDay: DayKey(year: 2026, month: 11, day: 7))
        let days = (0..<7).map { DayKey(year: 2026, month: 11, day: 7).adding(days: $0, calendar: cal) }
        let made = RecurrenceExpander.occurrences(for: [series], days: days, existing: [], calendar: cal, now: TestClock.at(8))
        // Sat 7 → Fri 13: Mon–Fri = 5 occurrences.
        XCTAssertEqual(made.count, 5)
        XCTAssertEqual(cal.component(.hour, from: made[0].start), 9)
        XCTAssertEqual(cal.component(.minute, from: made[0].start), 30)
        XCTAssertTrue(made.allSatisfy { $0.seriesID == series.id && $0.source == .recurrence })
    }

    func testRepeatRuleCodableRoundTrip() throws {
        let rule = RepeatRule.weekly(days: [2, 4, 6])
        let data = try JSONEncoder().encode(rule)
        XCTAssertEqual(try JSONDecoder().decode(RepeatRule.self, from: data), rule)
    }
}

final class NotificationPlannerTests: XCTestCase {
    func testLeadRemindersRespectBudgetAndOverrides() {
        var tasks: [PlanTask] = []
        for i in 0..<80 { tasks.append(task("T\(i)", 10, 0, minutes: 5, day: 7 + i / 14).with { $0.start += TimeInterval((i % 14) * 600) }) }
        tasks[0].leadTimeMinutes = 15
        tasks[1].remind = false
        var settings = PlannerSettings()
        settings.defaultLeadMinutes = 5
        let specs = NotificationPlanner.plan(tasks: tasks, settings: settings, now: TestClock.at(9), calendar: TestClock.calendar, timeFormatter: { _ in "x" })
        XCTAssertEqual(specs.count, NotificationPlanner.reminderBudget)
        let first = specs.first { $0.taskID == tasks[0].id }
        XCTAssertEqual(first?.fireDate, TestClock.at(9, 45))
        XCTAssertNil(specs.first { $0.taskID == tasks[1].id })
        XCTAssertTrue(specs.allSatisfy { $0.kind == .leadReminder && $0.categoryID == NotificationSpec.categoryLead })
    }

    func testRunningTaskGetsTimerAndNudge() throws {
        let running = try TaskTransitions.apply(.start, to: task("Focus", 10, 0, minutes: 25), at: TestClock.at(9, 58))
        let specs = NotificationPlanner.plan(tasks: [running], settings: PlannerSettings(), now: TestClock.at(10), calendar: TestClock.calendar, timeFormatter: { _ in "" })
        XCTAssertEqual(specs.map(\.kind), [.timerEnded, .overrunNudge])
        XCTAssertEqual(specs[0].fireDate, TestClock.at(10, 23))
        XCTAssertEqual(specs[1].fireDate, TestClock.at(10, 33))
    }

    func testInsideLeadWindowCatchUpOnlyForFreshEditsAndOnlyOnce() {
        var t = task("Soon", 9, 3, minutes: 30)
        // Old task inside its window: its reminder already fired → nothing new.
        XCTAssertTrue(NotificationPlanner.plan(tasks: [t], settings: PlannerSettings(), now: TestClock.at(9), calendar: TestClock.calendar, timeFormatter: { _ in "" }).isEmpty)
        // Just created: one catch-up with the real minutes left.
        t.updatedAt = TestClock.at(8, 59)
        let first = NotificationPlanner.plan(tasks: [t], settings: PlannerSettings(), now: TestClock.at(9), calendar: TestClock.calendar, timeFormatter: { _ in "" })
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].title, "Soon in 3 min")
        // A resync a minute later produces the same id (no duplicate) and, once delivered, nothing.
        let second = NotificationPlanner.plan(tasks: [t], settings: PlannerSettings(), now: TestClock.at(9, 1), calendar: TestClock.calendar, timeFormatter: { _ in "" })
        XCTAssertEqual(second.map(\.id), first.map(\.id))
        XCTAssertTrue(NotificationPlanner.diff(desired: second, pendingIDs: [], deliveredIDs: Set(first.map(\.id))).add.isEmpty)
    }

    func testIDsAreStableAcrossNowAndChangeWithContent() {
        var t = task("Write", 11)
        let a = NotificationPlanner.plan(tasks: [t], settings: PlannerSettings(), now: TestClock.at(9), calendar: TestClock.calendar, timeFormatter: { _ in "x" })
        let b = NotificationPlanner.plan(tasks: [t], settings: PlannerSettings(), now: TestClock.at(9, 30), calendar: TestClock.calendar, timeFormatter: { _ in "x" })
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        t.title = "Write report"
        let c = NotificationPlanner.plan(tasks: [t], settings: PlannerSettings(), now: TestClock.at(9), calendar: TestClock.calendar, timeFormatter: { _ in "x" })
        XCTAssertNotEqual(a.map(\.id), c.map(\.id))
    }

    func testDiffOnlyTouchesOwnedChangedIDs() {
        let t = task("A", 11)
        let specs = NotificationPlanner.plan(tasks: [t], settings: PlannerSettings(), now: TestClock.at(9), calendar: TestClock.calendar, timeFormatter: { _ in "" })
        let pending: Set<String> = [specs[0].id, "lead.stale.1", "assistant.ready"]
        let diff = NotificationPlanner.diff(desired: specs, pendingIDs: pending)
        XCTAssertTrue(diff.add.isEmpty)
        XCTAssertEqual(diff.removeIDs, ["lead.stale.1"])
        XCTAssertEqual(NotificationPlanner.taskID(fromNotificationID: specs[0].id), t.id)
    }
}

extension PlanTask {
    func with(_ body: (inout PlanTask) -> Void) -> PlanTask {
        var copy = self
        body(&copy)
        return copy
    }
}
