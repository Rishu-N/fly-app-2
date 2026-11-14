import XCTest
@testable import PlannerCore

@MainActor
final class AssistantCalendarTests: XCTestCase {
    private let dentist = BusyBlock(id: "ev1", title: "Dentist (private)", start: TestClock.at(15), end: TestClock.at(15, 45))
    private let holiday = BusyBlock(id: "ev2", title: "Bank holiday", start: TestClock.at(0), end: TestClock.at(0, day: 8), isAllDay: true)

    private func executor(_ store: TaskStore, titles: Bool = false) -> ToolExecutor {
        let events = [dentist, holiday]
        return ToolExecutor(store: store, settings: PlannerSettings(), now: TestClock.at(9), shareNotes: false,
                            busy: { interval in events.filter { $0.end > interval.start && $0.start < interval.end } },
                            shareEventTitles: titles)
    }

    func testListTasksIncludesEventsAsBusyWithoutTitlesByDefault() async {
        let (store, _) = await makeStore([task("Write", 10)])
        var refs = TaskRefRegistry()
        let out = executor(store).listTasks(["start": "2026-11-07", "end": "2026-11-08"], refs: &refs)
        XCTAssertTrue(out.contains("e1|2026-11-07T15:00|45|Busy|calendar"), out)
        XCTAssertFalse(out.contains("Dentist"), "event titles are private unless shared")
        XCTAssertFalse(out.contains("Bank holiday"), "all-day events are not busy time")
        let withTitles = executor(store, titles: true).listTasks(["start": "2026-11-07", "end": "2026-11-08"], refs: &refs)
        XCTAssertTrue(withTitles.contains("Dentist (private)"))
        let without = executor(store).listTasks(["start": "2026-11-07", "end": "2026-11-08", "include_events": false], refs: &refs)
        XCTAssertFalse(without.contains("calendar_events"))
    }

    func testFreeSlotsAvoidEventsAndProposalsFlagOverlaps() async {
        let (store, _) = await makeStore([])
        let ex = executor(store)
        let slots = ex.findFreeSlots(["start": "2026-11-07T14:00", "end": "2026-11-07T17:00", "duration_minutes": 60, "count": 5])
        XCTAssertTrue(slots.contains("2026-11-07T14:00–15:00"), slots)
        XCTAssertTrue(slots.contains("2026-11-07T15:45–17:00"), slots)
        XCTAssertFalse(slots.contains("T15:00–"), slots)

        var proposal = Proposal(id: "cs_1")
        var refs = TaskRefRegistry()
        _ = ex.stage(.createTasks, args: ["tasks": [["title": "Gym", "start": "2026-11-07T15:30", "duration_minutes": 30]]], into: &proposal, refs: &refs)
        let notes = proposal.items.first?.notes ?? []
        XCTAssertTrue(notes.contains { $0.hasPrefix("Overlaps a calendar event 15:00") }, "\(notes)")
    }

    func testContextListsTodaysEvents() async {
        let (store, _) = await makeStore([])
        let rows = executor(store).eventRows(in: DayKey(year: 2026, month: 11, day: 7).interval(calendar: TestClock.calendar))
        let ctx = SystemPrompt.context(.init(now: TestClock.at(9), calendar: TestClock.calendar, uses24HourClock: true,
                                             settings: PlannerSettings(), activeTaskRow: nil, todayRows: [], eventRows: rows))
        XCTAssertTrue(ctx.contains("Calendar events today (read-only busy time):\ne1|2026-11-07T15:00|45|Busy|calendar"), ctx)
    }

    func testReasoningEffortGoesToAzureAndOpenRouterButNotLocalServers() throws {
        let azure = try AssistantEndpoint(baseURLString: "https://myres.openai.azure.com/openai/v1", apiKey: "k")
        let router = try AssistantEndpoint(baseURLString: "https://openrouter.ai/api/v1", apiKey: "k")
        let local = try AssistantEndpoint(baseURLString: "http://192.168.1.20:11434/v1", apiKey: "")
        let lookalike = try AssistantEndpoint(baseURLString: "https://openrouter.ai.evil.example/v1", apiKey: "")
        XCTAssertTrue(azure.acceptsReasoningEffort)
        XCTAssertTrue(router.acceptsReasoningEffort)
        XCTAssertFalse(local.acceptsReasoningEffort)
        XCTAssertFalse(lookalike.acceptsReasoningEffort)
    }

    func testShareEventTitlesDecodesWithDefault() throws {
        let s = try JSONDecoder().decode(AssistantSettings.self, from: Data(#"{"model":"gpt-6-luna"}"#.utf8))
        XCTAssertFalse(s.shareEventTitles)
    }
}
