import XCTest
@testable import PlannerCore

final class QuickAddParserTests: XCTestCase {
    let parser = QuickAddParser(calendar: TestClock.calendar)

    func testTimeAndDuration() {
        let r = parser.parse("gym 6:30pm 45m #health", now: TestClock.at(9))
        XCTAssertEqual(r.title, "Gym")
        XCTAssertEqual(r.start, TestClock.at(18, 30))
        XCTAssertEqual(r.durationMinutes, 45)
        XCTAssertEqual(r.category, .health)
    }

    func testBareHourResolvesToNextOccurrence() {
        XCTAssertEqual(parser.parse("gym 6:30 45m", now: TestClock.at(13)).start, TestClock.at(18, 30))
        XCTAssertEqual(parser.parse("gym 6:30 45m", now: TestClock.at(5)).start, TestClock.at(6, 30))
        XCTAssertEqual(parser.parse("standup 9", now: TestClock.at(8)).start, TestClock.at(9))
    }

    func testTwentyFourHourAndRanges() {
        let a = parser.parse("design review 14:00-15:30", now: TestClock.at(9))
        XCTAssertEqual(a.title, "Design review")
        XCTAssertEqual(a.start, TestClock.at(14))
        XCTAssertEqual(a.durationMinutes, 90)

        let b = parser.parse("call 2-3pm", now: TestClock.at(9))
        XCTAssertEqual(b.start, TestClock.at(14))
        XCTAssertEqual(b.durationMinutes, 60)

        let c = parser.parse("workshop 11-1pm", now: TestClock.at(9))
        XCTAssertEqual(c.start, TestClock.at(11))
        XCTAssertEqual(c.durationMinutes, 120)

        let d = parser.parse("focus from 9 to 11", now: TestClock.at(8))
        XCTAssertEqual(d.title, "Focus")
        XCTAssertEqual(d.start, TestClock.at(9))
        XCTAssertEqual(d.durationMinutes, 120)
    }

    func testDurationsVariants() {
        XCTAssertEqual(parser.parse("deep work 90m", now: TestClock.at(9)).durationMinutes, 90)
        XCTAssertEqual(parser.parse("deep work 1h30", now: TestClock.at(9)).durationMinutes, 90)
        XCTAssertEqual(parser.parse("deep work 1.5h", now: TestClock.at(9)).durationMinutes, 90)
        XCTAssertEqual(parser.parse("deep work for 2 hours", now: TestClock.at(9)).durationMinutes, 120)
        XCTAssertEqual(parser.parse("nap 20 min", now: TestClock.at(9)).durationMinutes, 20)
        XCTAssertNil(parser.parse("deep work 90m", now: TestClock.at(9)).start)
    }

    func testDaysAndWeekdays() {
        let t = parser.parse("call mum tomorrow 7pm", now: TestClock.at(9))
        XCTAssertEqual(t.title, "Call mum")
        XCTAssertEqual(t.start, TestClock.at(19, day: 8))
        // 2026-11-07 is a Saturday; "mon" → Nov 9.
        let m = parser.parse("dentist mon 3pm 40m", now: TestClock.at(9))
        XCTAssertEqual(m.start, TestClock.at(15, day: 9))
        XCTAssertEqual(m.durationMinutes, 40)
        XCTAssertEqual(m.title, "Dentist")
    }

    func testDoesNotEatNumbersInTitles() {
        let r = parser.parse("answer 3 emails 20m", now: TestClock.at(9))
        XCTAssertEqual(r.durationMinutes, 20)
        XCTAssertEqual(r.title, "Answer 3 emails")
        XCTAssertNil(r.start)
        XCTAssertEqual(parser.parse("gym 6 45m", now: TestClock.at(9)).start, TestClock.at(18))
    }

    func testAtConnectorAndNoon() {
        let r = parser.parse("lunch with Sam at noon 1h", now: TestClock.at(9))
        XCTAssertEqual(r.title, "Lunch with Sam")
        XCTAssertEqual(r.start, TestClock.at(12))
        XCTAssertEqual(r.durationMinutes, 60)
    }
}

final class QuickAddRegressionTests: XCTestCase {
    let parser = QuickAddParser(calendar: TestClock.calendar)

    func testAmbiguousRangeAfterItsMorningTimeStaysShort() {
        let r = parser.parse("standup 9-9:15", now: TestClock.at(10))
        XCTAssertEqual(r.start, TestClock.at(21))
        XCTAssertEqual(r.durationMinutes, 15)
        let f = parser.parse("focus from 9 to 11", now: TestClock.at(13))
        XCTAssertEqual(f.durationMinutes, 120)
    }

    func testTonightMeansEvening() {
        XCTAssertEqual(parser.parse("movie tonight 8", now: TestClock.at(9)).start, TestClock.at(20))
        XCTAssertEqual(parser.parse("call today 6", now: TestClock.at(13)).start, TestClock.at(18))
    }

    func testOvernightRange() {
        let r = parser.parse("deploy 22:00-01:00", now: TestClock.at(9))
        XCTAssertEqual(r.start, TestClock.at(22))
        XCTAssertEqual(r.durationMinutes, 180)
    }
}
