import XCTest
@testable import PlannerCore

/// One scripted conversation per prompt template (PromptTemplate.library), asserting the tool
/// results the model sees, the review card, conflict notes, apply/undo, and the exact wire.
/// TestClock: Saturday 2026-11-07, Europe/London (UTC+0), day window 07:00–22:00.
@MainActor
final class AssistantScenarioTests: XCTestCase {
    func template(_ id: String, _ values: [String: String] = [:]) -> String {
        let t = PromptTemplate.library.first { $0.id == id }!
        var filled = t.hints
        for (k, v) in values { filled[k] = v }
        let text = t.render(filled)
        XCTAssertFalse(text.contains("{"), "unfilled placeholder in \(id)")
        return text
    }

    // MARK: 1. Plan my day — list_tasks → find_free_slots → create_tasks

    func testPlanMyDay() async throws {
        let standup = task("Standup", 10, minutes: 15, category: .meeting)
        let lunch = task("Lunch with Sam", 12, 30, minutes: 60, category: .social)
        let (store, _) = await makeStore([standup, lunch])
        let model = QAModel([
            .reply("", [call("call_list", "list_tasks", #"{"start":"2026-11-07T09:00","end":"2026-11-07T18:00"}"#)]),
            .reply("", [call("call_free", "find_free_slots", #"{"start":"2026-11-07T09:00","end":"2026-11-07T18:00","duration_minutes":60,"count":3}"#)]),
            .reply("Here's a plan for today.", [call("call_create", "create_tasks", #"""
            {"summary":"Today's plan","tasks":[
              {"title":"Report","start":"2026-11-07T09:00","duration_minutes":60,"category":"focus"},
              {"title":"Break","start":"2026-11-07T10:15","duration_minutes":10},
              {"title":"Report (part 2)","start":"2026-11-07T10:25","duration_minutes":90,"category":"deep work"},
              {"title":"Inbox zero","start":"2026-11-07T13:00","duration_minutes":30,"category":"admin"},
              {"title":"Gym","start":"2026-11-07T17:00","duration_minutes":60}]}
            """#)]),
            .reply("You're welcome."),
            .reply("Okay."),
        ])
        let h = QAHarness(store: store, transport: model)
        let text = template("plan-day", ["must_dos": "Report, gym", "nice_to_haves": "Inbox zero"])
        XCTAssertTrue(text.hasPrefix("Plan today from now to 18:00. Must-dos: Report, gym. Nice-to-haves: Inbox zero."))
        await h.send(text)

        // Three round trips; each request answers the previous round's tool calls.
        XCTAssertEqual(h.requests.count, 3)
        XCTAssertEqual(h.signature(0), ["prompt:static", "prompt:context", "user:" + text])
        XCTAssertEqual(h.signature(1), ["prompt:static", "prompt:context", "user:" + text,
                                        "assistant:[call_list:list_tasks]", "tool:call_list"])
        XCTAssertEqual(h.signature(2), ["prompt:static", "prompt:context", "user:" + text,
                                        "assistant:[call_list:list_tasks]", "tool:call_list",
                                        "assistant:[call_free:find_free_slots]", "tool:call_free"])
        XCTAssertTrue(h.context(0).contains("Today:\nt1|2026-11-07T10:00|15|Standup|meeting|upcoming|\nt2|2026-11-07T12:30|60|Lunch with Sam|social|upcoming|"))
        XCTAssertEqual(h.toolResult(1, "call_list"),
                       #"{"columns":"id|start|minutes|title|category|state|flags","count":2,"rows":["t1|2026-11-07T10:00|15|Standup|meeting|upcoming|","t2|2026-11-07T12:30|60|Lunch with Sam|social|upcoming|"]}"#)
        XCTAssertEqual(h.toolResult(2, "call_free"),
                       #"{"slots":["2026-11-07T09:00–10:00 (60m free)","2026-11-07T10:15–12:30 (135m free)","2026-11-07T13:30–18:00 (270m free)"]}"#)

        // Review card.
        XCTAssertEqual(h.layout, ["user", "assistant", "proposal"])
        XCTAssertEqual(h.assistantTexts, ["Here's a plan for today."])
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.id, "cs_1")
        XCTAssertEqual(p.summary, "Today's plan")
        XCTAssertEqual(p.items.map(\.kind), [.add, .add, .add, .add, .add])
        XCTAssertEqual(p.items.map { $0.after!.title }, ["Report", "Break", "Report (part 2)", "Inbox zero", "Gym"])
        XCTAssertEqual(p.items.map { $0.after!.category }, [.focus, .rest, .focus, .admin, .health])
        XCTAssertEqual(p.items.map { $0.after!.durationMinutes }, [60, 10, 90, 30, 60])
        XCTAssertEqual(p.items.map(\.notes), [[], [], [], ["Overlaps Lunch with Sam 12:30–13:30"], []])
        XCTAssertTrue(p.items.allSatisfy { $0.isSelected && $0.after?.source == .assistant && $0.after?.status == .planned })
        XCTAssertEqual(h.reviewFlags, [true])
        XCTAssertEqual(store.tasksByID.count, 2, "nothing is saved before Apply")

        // The ack the model got for create_tasks (kept in the wire).
        let ack = try XCTUnwrap(JSONValue.parse(h.session.transcript.wire.last!.content!))
        XCTAssertEqual(ack["status"]?.string, "proposed")
        XCTAssertEqual(ack["change_set_id"]?.string, "cs_1")
        XCTAssertEqual(ack["items"]?.array?.count, 5)
        XCTAssertEqual(ack["items"]?.array?[3]["conflicts"], ["Overlaps Lunch with Sam 12:30–13:30"])
        XCTAssertEqual(ack["items"]?.array?[3]["summary"]?.string, "Inbox zero 2026-11-07T13:00–13:30")

        // Apply, then the outcome is reported on the next turn and earlier tool payloads are compacted.
        h.session.apply(p.id)
        XCTAssertEqual(store.tasksByID.count, 7)
        XCTAssertEqual(h.proposal("cs_1")?.state, .applied(count: 5, total: 5))
        await h.send("Thanks")
        XCTAssertEqual(h.signature(3), ["prompt:static", "user:" + text, "assistant:Here's a plan for today.", "prompt:context",
                                        "user:" + h.lastUserContent(3)])
        let note = h.lastUserContent(3)
        XCTAssertTrue(note.hasPrefix("(App note: User applied cs_1 (5 of 5 changes: "), note)
        XCTAssertTrue(note.hasSuffix(")\n\nThanks"), note)
        for title in ["Report", "Break", "Inbox zero", "Gym"] { XCTAssertTrue(note.contains(title)) }
        XCTAssertTrue(h.context(3).contains("|2026-11-07T17:00|60|Gym|health|upcoming|"), "applied tasks appear in the next CONTEXT")

        // Undo restores the schedule and is reported too.
        h.session.undo(p.id)
        XCTAssertEqual(Set(store.tasksByID.keys), [standup.id, lunch.id])
        XCTAssertEqual(h.proposal("cs_1")?.state, .undone)
        await h.send("Hmm")
        XCTAssertTrue(h.lastUserContent(4).hasPrefix("(App note: User undid cs_1; those changes were reverted.)\n\nHmm"))
        for r in h.requests { QAHarness.assertWireIsValid(r.messages) }
    }

    // MARK: 2. Running late — shift_tasks (explicit subset; meetings stay put)

    func testRunningLateShiftsOnlyTheChosenTasks() async throws {
        let breakfast = task("Breakfast", 8, minutes: 20, status: .completed, category: .personal)
        let email = task("Email triage", 9, minutes: 30, category: .admin)
        let prep = task("Prep notes", 9, 45, minutes: 15)
        let standup = task("Standup", 10, minutes: 15, category: .meeting)
        let review = task("Design review", 11, minutes: 60, category: .meeting)
        let (store, _) = await makeStore([breakfast, email, prep, standup, review], now: TestClock.at(9, 10))
        let model = QAModel([
            .reply("Pushed your non-meeting tasks back 15 minutes.", [
                call("call_shift", "shift_tasks", #"{"date":"2026-11-07","after":"09:00","minutes":15,"task_ids":["t2","t3"]}"#),
            ]),
        ])
        let h = QAHarness(store: store, transport: model, now: TestClock.at(9, 10))
        let text = template("running-late", ["keep_fixed": "meetings"])
        XCTAssertEqual(text, "I'm running 15 minutes late. Reschedule the rest of today from now. Don't move meetings. If it won't all fit, shorten or drop the lowest-priority items and suggest moving them to tomorrow.")
        await h.send(text)

        XCTAssertTrue(h.context(0).contains("""
        t1|2026-11-07T08:00|20|Breakfast|personal|completed|
        t2|2026-11-07T09:00|30|Email triage|admin|due|
        t3|2026-11-07T09:45|15|Prep notes|focus|upcoming|
        t4|2026-11-07T10:00|15|Standup|meeting|upcoming|
        """))
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.items.map(\.kind), [.move, .move])
        XCTAssertEqual(p.items.map { $0.before!.title }, ["Email triage", "Prep notes"])
        XCTAssertEqual(p.items.map { $0.after!.start }, [TestClock.at(9, 15), TestClock.at(10)])
        XCTAssertEqual(p.items[1].notes, ["Overlaps Standup 10:00–10:15"], "the meeting that stays put is flagged")
        XCTAssertEqual(p.items[0].notes, [])

        h.session.apply(p.id)
        XCTAssertEqual(store.task(email.id)?.start, TestClock.at(9, 15))
        XCTAssertEqual(store.task(prep.id)?.start, TestClock.at(10))
        XCTAssertEqual(store.task(standup.id)?.start, TestClock.at(10))
        XCTAssertEqual(store.task(review.id)?.start, TestClock.at(11))
        XCTAssertEqual(store.task(breakfast.id)?.status, .completed)
    }

    /// Without a subset everything not started moves; the running task never does; the user
    /// unticks the meetings and applies only the rest.
    func testRunningLateApplySelected() async throws {
        let email = task("Email triage", 9, minutes: 30, category: .admin)
        let sweep = task("Inbox sweep", 9, 5, minutes: 30, category: .admin)
        let prep = task("Prep notes", 9, 45, minutes: 15)
        let standup = task("Standup", 10, minutes: 15, category: .meeting)
        let review = task("Design review", 11, minutes: 60, category: .meeting)
        let (store, _) = await makeStore([email, sweep, prep, standup, review], now: TestClock.at(9, 10))
        try store.perform(.start, on: sweep.id, at: TestClock.at(9, 5))
        let model = QAModel([
            .reply("", [call("c1", "shift_tasks", #"{"date":"2026-11-07","after":"09:00","minutes":15}"#)]),
            .reply("Noted."),
        ])
        let h = QAHarness(store: store, transport: model, now: TestClock.at(9, 10))
        await h.send(template("running-late", ["keep_fixed": "meetings"]))

        XCTAssertTrue(h.context(0).contains("Active task: t2|2026-11-07T09:05|30|Inbox sweep|admin|running|ends 09:35"), h.context(0))
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.items.map { $0.before!.title }, ["Email triage", "Prep notes", "Standup", "Design review"])
        XCTAssertFalse(p.items.contains { $0.targetID == sweep.id }, "a running task is never shifted")
        for item in p.items where item.before!.category == .meeting { h.session.toggle(item.id, inProposal: p.id) }
        XCTAssertEqual(h.proposal(p.id)?.selectedCount, 2)

        h.session.apply(p.id)
        XCTAssertEqual(h.proposal(p.id)?.state, .applied(count: 2, total: 4))
        XCTAssertEqual(store.task(email.id)?.start, TestClock.at(9, 15))
        XCTAssertEqual(store.task(prep.id)?.start, TestClock.at(10))
        XCTAssertEqual(store.task(standup.id)?.start, TestClock.at(10))
        XCTAssertEqual(store.task(review.id)?.start, TestClock.at(11))
        XCTAssertEqual(store.task(sweep.id)?.status, .running)
        XCTAssertNotNil(store.task(sweep.id)?.session)

        await h.send("ok")
        XCTAssertTrue(h.lastUserContent(1).hasPrefix("(App note: User applied cs_1 (2 of 4 changes: "))
    }

    // MARK: 3. Quick add — create_tasks; a bad row is corrected in round 2 into the same card

    func testQuickAddWithSelfCorrection() async throws {
        let (store, _) = await makeStore([])
        let model = QAModel([
            .reply("", [call("c1", "create_tasks", #"""
            {"tasks":[
              {"title":"Dentist","start":"2026-11-07T15:00","duration_minutes":30,"reminder_minutes":5,"category":"personal"},
              {"title":"Groceries","start":"2026-11-07T17:30","duration_minutes":30,"reminder_minutes":5,"category":"errands"},
              {"title":"Call mum","start":"2026-11-07T18:00","reminder_minutes":5},
              {"title":"Call plumber","start":"tomorrow 9am","duration_minutes":15}]}
            """#)]),
            .reply("Added all four — ready to review.", [call("c2", "create_tasks", #"{"tasks":[{"title":"Call plumber","start":"2026-11-08T09:00","duration_minutes":15,"reminder_minutes":5}]}"#)]),
        ])
        let h = QAHarness(store: store, transport: model)
        let text = template("quick-add", ["tasks": "dentist at 3pm, groceries after work, call mum at 6, call plumber tomorrow 9am"])
        await h.send(text)

        XCTAssertEqual(h.requests.count, 2, "a row error makes the model try again")
        let ack = try XCTUnwrap(h.toolJSON(1, "c1"))
        XCTAssertEqual(ack["status"]?.string, "proposed")
        XCTAssertEqual(ack["errors"], ["Call plumber: start must be YYYY-MM-DDTHH:MM"])
        XCTAssertEqual(ack["items"]?.array?.count, 3)

        XCTAssertEqual(h.proposals.count, 1, "both rounds land on one review card")
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.id, "cs_1")
        XCTAssertEqual(p.items.map { $0.after!.title }, ["Dentist", "Groceries", "Call mum", "Call plumber"])
        XCTAssertEqual(p.items.map { $0.after!.category }, [.personal, .admin, .meeting, .meeting])
        XCTAssertEqual(p.items.map { $0.after!.durationMinutes }, [30, 30, 30, 15], "missing duration uses the default")
        XCTAssertEqual(p.items.map { $0.after!.leadTimeMinutes }, [5, 5, 5, 5])
        XCTAssertEqual(p.items[3].after!.start, TestClock.at(9, day: 8))
        XCTAssertEqual(h.layout, ["user", "assistant", "proposal"])

        h.session.apply(p.id)
        XCTAssertEqual(store.tasksByID.count, 4)
        XCTAssertTrue(store.tasksByID.values.allSatisfy { $0.source == .assistant && $0.remind && $0.status == .planned })
    }

    // MARK: 4. Break it down — find_free_slots → create + delete the original

    func testBreakItDownReplacesTheOriginal() async throws {
        let original = task("Write launch report", 14, minutes: 120)
        let (store, _) = await makeStore([original])
        let model = QAModel([
            .reply("", [call("c_free", "find_free_slots", #"{"start":"2026-11-07T09:00","end":"2026-11-07T22:00","duration_minutes":120,"count":1}"#)]),
            .reply("Split into four 25-minute blocks this morning.", [
                call("c_create", "create_tasks", #"""
                {"summary":"Launch report in 25-min blocks","tasks":[
                  {"title":"Write launch report 1/4","start":"2026-11-07T09:00","duration_minutes":25,"category":"focus"},
                  {"title":"Write launch report 2/4","start":"2026-11-07T09:30","duration_minutes":25,"category":"focus"},
                  {"title":"Write launch report 3/4","start":"2026-11-07T10:00","duration_minutes":25,"category":"focus"},
                  {"title":"Write launch report 4/4","start":"2026-11-07T10:30","duration_minutes":25,"category":"focus"}]}
                """#),
                call("c_delete", "delete_tasks", #"{"ids":["t1"],"reason":"Split into 25-min blocks"}"#),
            ]),
        ])
        let h = QAHarness(store: store, transport: model)
        await h.send(template("break-down"))

        XCTAssertEqual(h.toolResult(1, "c_free"), #"{"slots":["2026-11-07T09:00–14:00 (300m free)"]}"#)
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.summary, "Launch report in 25-min blocks")
        XCTAssertEqual(p.items.map(\.kind), [.add, .add, .add, .add, .remove])
        XCTAssertEqual(p.items.last?.before?.id, original.id)
        XCTAssertEqual(p.items.last?.notes, ["Split into 25-min blocks"])
        XCTAssertTrue(p.items.allSatisfy { !$0.notes.contains { $0.hasPrefix("Overlaps") } })
        let deleteAck = try XCTUnwrap(JSONValue.parse(h.session.transcript.wire.last!.content!))
        XCTAssertEqual(deleteAck["items"]?.array?.first?["change"]?.string, "remove")
        XCTAssertEqual(deleteAck["items"]?.array?.first?["summary"]?.string, "Write launch report 2026-11-07T14:00–16:00")

        h.session.apply(p.id)
        XCTAssertNil(store.task(original.id))
        XCTAssertEqual(store.tasksByID.values.map(\.title).sorted(), ["Write launch report 1/4", "Write launch report 2/4", "Write launch report 3/4", "Write launch report 4/4"])
        h.session.undo(p.id)
        XCTAssertEqual(Array(store.tasksByID.keys), [original.id])
        XCTAssertEqual(store.task(original.id)?.start, TestClock.at(14))
    }

    /// Variant: shorten and move the original instead of deleting it.
    func testBreakItDownShortensTheOriginal() async throws {
        let original = task("Write launch report", 14, minutes: 120)
        let (store, _) = await makeStore([original])
        let model = QAModel([
            .reply("", [
                call("a", "create_tasks", #"{"tasks":[{"title":"Write launch report 1/4","start":"2026-11-07T09:00","duration_minutes":25},{"title":"Write launch report 2/4","start":"2026-11-07T09:30","duration_minutes":25},{"title":"Write launch report 3/4","start":"2026-11-07T10:00","duration_minutes":25}]}"#),
                call("b", "update_tasks", #"{"updates":[{"id":"t1","title":"Write launch report 4/4","start":"2026-11-07T10:30","duration_minutes":25}]}"#),
            ]),
        ])
        let h = QAHarness(store: store, transport: model)
        await h.send(template("break-down"))
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.items.map(\.kind), [.add, .add, .add, .move])
        XCTAssertEqual(p.items[3].before?.start, TestClock.at(14))
        XCTAssertEqual(p.items[3].after?.start, TestClock.at(10, 30))
        XCTAssertEqual(p.items[3].after?.title, "Write launch report 4/4")
        XCTAssertTrue(p.items.allSatisfy(\.notes.isEmpty))
        h.session.apply(p.id)
        XCTAssertEqual(store.tasksByID.count, 4)
        XCTAssertEqual(store.task(original.id)?.durationMinutes, 25)
    }

    // MARK: 5. Find free time — find_free_slots → ask_user → create_tasks

    func testFindFreeTimeAsksWhichSlot() async throws {
        let standup = task("Standup", 10, minutes: 15, category: .meeting)
        let lunch = task("Lunch", 12, minutes: 60, category: .social)
        let brunch = task("Brunch", 11, minutes: 90, day: 8, category: .social)
        let (store, _) = await makeStore([standup, lunch, brunch])
        let model = QAModel([
            .reply("", [call("c_free", "find_free_slots", #"{"start":"2026-11-07T12:00","end":"2026-11-09T17:00","duration_minutes":60,"count":3,"within_day_window":true}"#)]),
            .reply("Here are three options.", [call("c_ask", "ask_user", #"{"question":"Which slot should I book for deep work?","options":["Sat 13:00","Sun 07:00","Sun 12:30"]}"#)]),
            .reply("", [call("c_create", "create_tasks", #"{"tasks":[{"title":"Deep work","start":"2026-11-08T12:30","duration_minutes":60,"category":"focus"}]}"#)]),
        ])
        let h = QAHarness(store: store, transport: model)
        await h.send(template("free-time"))

        XCTAssertEqual(h.toolResult(1, "c_free"),
                       #"{"slots":["2026-11-07T13:00–22:00 (540m free)","2026-11-08T07:00–11:00 (240m free)","2026-11-08T12:30–22:00 (570m free)"]}"#)
        XCTAssertEqual(h.requests.count, 2, "ask_user pauses the loop")
        let pending = try XCTUnwrap(h.session.pendingQuestion)
        XCTAssertEqual(pending.question.text, "Which slot should I book for deep work?")
        XCTAssertEqual(pending.question.options, ["Sat 13:00", "Sun 07:00", "Sun 12:30"])
        XCTAssertTrue(pending.question.allowFreeText)
        XCTAssertEqual(h.reviewFlags, [true])
        XCTAssertFalse(h.session.isRunning)

        await h.answer("Sun 12:30")
        XCTAssertEqual(Array(h.signature(2).suffix(4)), ["assistant:[c_free:find_free_slots]", "tool:c_free", "assistant:Here are three options.[c_ask:ask_user]", "tool:c_ask"])
        XCTAssertEqual(h.toolResult(2, "c_ask"), #"{"answer":"Sun 12:30"}"#)
        XCTAssertNil(h.session.pendingQuestion)
        XCTAssertEqual(h.questions.first?.answer, "Sun 12:30")
        XCTAssertEqual(h.layout, ["user", "assistant", "question", "user", "proposal"])
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.items.first?.after?.start, TestClock.at(12, 30, day: 8))
        XCTAssertEqual(p.items.first?.notes, [])
    }

    // MARK: 6. Move tasks — two parallel list_tasks → update_tasks

    func testMoveTasksByCategory() async throws {
        let deep = task("Deep work", 9, 30, minutes: 90)
        let expenses = task("Expenses", 11, minutes: 30, category: .admin)
        let invoices = task("Pay invoices", 15, minutes: 30, category: .admin)
        let football = task("Football", 15, minutes: 90, day: 8, category: .health)
        let (store, _) = await makeStore([deep, expenses, invoices, football])
        let model = QAModel([
            .reply("", [
                call("c_today", "list_tasks", #"{"start":"2026-11-07","end":"2026-11-08","query":"admin"}"#),
                call("c_tomorrow", "list_tasks", #"{"start":"2026-11-08","end":"2026-11-09"}"#),
            ]),
            .reply("Moved both admin tasks to tomorrow at the same times.", [
                call("c_move", "update_tasks", #"{"updates":[{"id":"t2","start":"2026-11-08T11:00"},{"id":"t3","start":"2026-11-08T15:00"}]}"#),
            ]),
        ])
        let h = QAHarness(store: store, transport: model)
        await h.send(template("move-tasks"))

        XCTAssertEqual(Array(h.signature(1).suffix(3)), ["assistant:[c_today:list_tasks,c_tomorrow:list_tasks]", "tool:c_today", "tool:c_tomorrow"])
        XCTAssertEqual(h.toolJSON(1, "c_today")?["rows"], ["t2|2026-11-07T11:00|30|Expenses|admin|upcoming|", "t3|2026-11-07T15:00|30|Pay invoices|admin|upcoming|"])
        XCTAssertEqual(h.toolJSON(1, "c_tomorrow")?["rows"], ["t4|2026-11-08T15:00|90|Football|health|upcoming|"])
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.items.map(\.kind), [.move, .move])
        XCTAssertEqual(p.items.map(\.notes), [[], ["Overlaps Football 15:00–16:30"]])
        h.session.apply(p.id)
        XCTAssertEqual(store.task(expenses.id)?.start, TestClock.at(11, day: 8))
        XCTAssertEqual(store.task(invoices.id)?.start, TestClock.at(15, day: 8))
        XCTAssertEqual(store.task(deep.id)?.start, TestClock.at(9, 30))
    }

    // MARK: 7. Clear a block — list_tasks(range) → find_free_slots → update_tasks

    func testClearABlockKeepsMeetings() async throws {
        let codeReview = task("Code review", 13, 30, minutes: 60)
        let oneOnOne = task("1:1 with Ana", 14, 30, minutes: 30, category: .meeting)
        let docs = task("Docs", 15, minutes: 45)
        let gym = task("Gym", 18, minutes: 60, category: .health)
        let (store, _) = await makeStore([codeReview, oneOnOne, docs, gym])
        let model = QAModel([
            .reply("", [call("a", "list_tasks", #"{"start":"2026-11-07T14:00","end":"2026-11-07T16:00"}"#)]),
            .reply("", [call("b", "find_free_slots", #"{"start":"2026-11-07T16:00","end":"2026-11-07T22:00","duration_minutes":45,"count":3}"#)]),
            .reply("Cleared 14:00–16:00 except your 1:1.", [call("c", "update_tasks", #"{"updates":[{"id":"t1","start":"2026-11-07T16:00"},{"id":"t3","start":"2026-11-07T17:00"}]}"#)]),
        ])
        let h = QAHarness(store: store, transport: model)
        await h.send(template("clear-block"))
        XCTAssertEqual(h.toolJSON(1, "a")?["rows"]?.array?.compactMap(\.string).map { $0.split(separator: "|")[3] }, ["Code review", "1:1 with Ana", "Docs"],
                       "tasks overlapping the start of the range are included")
        XCTAssertEqual(h.toolResult(2, "b"), #"{"slots":["2026-11-07T16:00–18:00 (120m free)","2026-11-07T19:00–22:00 (180m free)"]}"#)
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertTrue(p.items.allSatisfy(\.notes.isEmpty))
        h.session.apply(p.id)
        let block = store.tasks(in: DateInterval(start: TestClock.at(14), end: TestClock.at(16)))
        XCTAssertEqual(block.map(\.title), ["1:1 with Ana"])
    }

    // MARK: 8. Daily review — list_tasks(include_done) → update_tasks (a closed task is refused)

    func testDailyReviewRollsOverUnfinished() async throws {
        let tests = task("Write tests", 9, minutes: 60, status: .completed)
        let gym = task("Gym", 12, minutes: 60, status: .skipped, category: .health)
        let read = task("Read", 15, minutes: 30, category: .learning)
        let plan = task("Plan tomorrow", 20, minutes: 30, category: .admin)
        let (store, _) = await makeStore([tests, gym, read, plan], now: TestClock.at(21))
        let model = QAModel([
            .reply("", [call("l", "list_tasks", #"{"start":"2026-11-07","end":"2026-11-08","include_done":true}"#)]),
            .reply("1. You finished your main task.\n2. Gym was skipped.\n3. Two tasks slipped.", [
                call("u", "update_tasks", #"{"updates":[{"id":"t3","start":"2026-11-08T10:00"},{"id":"t4","start":"2026-11-08T08:30"},{"id":"t1","start":"2026-11-08T09:00"}]}"#),
            ]),
            .reply("Read and Plan tomorrow are moved to tomorrow — ready to review."),
        ])
        let h = QAHarness(store: store, transport: model, now: TestClock.at(21))
        await h.send(template("daily-review"))

        XCTAssertEqual(h.toolJSON(1, "l")?["rows"], [
            "t1|2026-11-07T09:00|60|Write tests|focus|completed|",
            "t2|2026-11-07T12:00|60|Gym|health|skipped|",
            "t3|2026-11-07T15:00|30|Read|learning|missed|",
            "t4|2026-11-07T20:00|30|Plan tomorrow|admin|missed|",
        ])
        XCTAssertEqual(h.requests.count, 3, "the refused row makes the model follow up")
        let ack = try XCTUnwrap(h.toolJSON(2, "u"))
        XCTAssertEqual(ack["errors"], ["t1 is already completed; not moved"])
        XCTAssertEqual(ack["items"]?.array?.count, 2)
        XCTAssertEqual(h.layout, ["user", "assistant", "assistant", "proposal"])
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.items.map { $0.before!.title }, ["Read", "Plan tomorrow"])
        h.session.apply(p.id)
        XCTAssertEqual(store.task(read.id)?.start, TestClock.at(10, day: 8))
        XCTAssertEqual(store.task(plan.id)?.start, TestClock.at(8, 30, day: 8))
        XCTAssertEqual(store.task(tests.id)?.start, TestClock.at(9))
        XCTAssertEqual(store.task(tests.id)?.status, .completed)
    }

    // MARK: 9. Weekly planning — list → create (two routines + one-offs)

    func testWeeklyPlanningWithRoutines() async throws {
        let dentist = task("Dentist", 14, minutes: 60, day: 9, category: .personal)
        let (store, _) = await makeStore([dentist])
        let model = QAModel([
            .reply("", [call("l", "list_tasks", #"{"start":"2026-11-09","end":"2026-11-14"}"#)]),
            .reply("Here's the week.", [call("c", "create_tasks", #"""
            {"summary":"Week of 9 Nov","tasks":[
              {"title":"Standup","start":"2026-11-09T09:30","duration_minutes":15,"category":"meeting","repeat":{"frequency":"weekdays"}},
              {"title":"Run","start":"2026-11-09T18:00","duration_minutes":45,"category":"health","repeat":{"frequency":"weekly","weekdays":["mon","wed","fri"]}},
              {"title":"Ship v1: deep work","start":"2026-11-09T10:00","duration_minutes":180,"category":"focus"},
              {"title":"Ship v1: deep work","start":"2026-11-10T14:00","duration_minutes":180,"category":"focus"},
              {"title":"Ship v1: wrap-up","start":"2026-11-09T13:30","duration_minutes":60,"category":"focus"}]}
            """#)]),
        ])
        let h = QAHarness(store: store, transport: model)
        await h.send(template("weekly-plan"))

        XCTAssertTrue(h.context(0).contains("Today:\n(nothing scheduled)"))
        XCTAssertEqual(h.toolJSON(1, "l")?["rows"], ["t1|2026-11-09T14:00|60|Dentist|personal|upcoming|"])
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.items.map(\.kind), [.addRoutine, .addRoutine, .add, .add, .add])
        XCTAssertEqual(p.items[0].notes, ["Weekdays"])
        XCTAssertEqual(p.items[1].notes, ["Every Mon, Wed, Fri"])
        XCTAssertEqual(p.items[0].after?.start, TestClock.at(9, 30, day: 9))
        XCTAssertEqual(p.items[4].notes, ["Overlaps Dentist 14:00–15:00"])

        h.session.apply(p.id)
        XCTAssertEqual(store.series.count, 2)
        let tasks = Array(store.tasksByID.values)
        // Window is 14 days from Sat 7 Nov (7…20 Nov): 10 weekday standups, 6 Mon/Wed/Fri runs.
        XCTAssertEqual(tasks.filter { $0.title == "Standup" }.count, 10)
        XCTAssertEqual(tasks.filter { $0.title == "Run" }.count, 6)
        XCTAssertEqual(tasks.filter { $0.title.hasPrefix("Ship v1") }.count, 3)
        h.session.undo(p.id)
        XCTAssertTrue(store.series.isEmpty)
        XCTAssertEqual(Array(store.tasksByID.keys), [dentist.id])
    }

    // MARK: 10. Build a routine — create_tasks with repeat (starting on a non-matching day)

    func testBuildARoutineStartingOnASunday() async throws {
        let (store, _) = await makeStore([])
        let model = QAModel([
            .reply("Your weekday morning routine is ready to review.", [call("c", "create_tasks", #"""
            {"summary":"Morning routine","tasks":[
              {"title":"Stretch","start":"2026-11-08T07:00","duration_minutes":10,"category":"health","repeat":{"frequency":"weekdays"}},
              {"title":"Journal","start":"2026-11-08T07:10","duration_minutes":10,"category":"personal","repeat":{"frequency":"weekdays"}},
              {"title":"Plan day","start":"2026-11-08T07:20","duration_minutes":5,"category":"admin","repeat":{"frequency":"weekdays"}}]}
            """#)]),
        ])
        let h = QAHarness(store: store, transport: model)
        let text = template("routine")
        XCTAssertEqual(text, "Create a recurring 'Morning' routine every weekday starting at 07:00: stretch 10m, journal 10m, plan day 5m. Start on tomorrow.")
        await h.send(text)

        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.items.map(\.kind), [.addRoutine, .addRoutine, .addRoutine])
        XCTAssertTrue(p.items.allSatisfy { $0.notes == ["Weekdays"] })
        // "Tomorrow" is Sunday; a weekday routine's first occurrence (the preview) is Monday.
        XCTAssertEqual(p.items.map { $0.after!.start }, [TestClock.at(7, day: 9), TestClock.at(7, 10, day: 9), TestClock.at(7, 20, day: 9)])
        XCTAssertTrue(p.items.allSatisfy { $0.notes.allSatisfy { !$0.hasPrefix("Overlaps") } }, "routine steps are back to back")

        h.session.apply(p.id)
        XCTAssertEqual(store.series.count, 3)
        XCTAssertEqual(store.tasksByID.count, 30, "3 steps × 10 weekdays in the 14-day window")
        for item in p.items { XCTAssertNotNil(store.task(item.after!.id), "the previewed occurrence is the one that gets created") }
    }

    // MARK: 11. Focus sprints — 8 back-to-back blocks

    func testFocusSprints() async throws {
        let standup = task("Standup", 10, minutes: 15, category: .meeting)
        let (store, _) = await makeStore([standup])
        var rows: [String] = []
        var t = 9 * 60
        for i in 1...4 {
            rows.append(#"{"title":"Thesis ch. 2 — sprint \#(i)","start":"2026-11-07T\#(String(format: "%02d:%02d", t / 60, t % 60))","duration_minutes":25,"category":"focus"}"#)
            t += 25
            let (title, minutes) = i == 4 ? ("Long break", 20) : ("Break", 5)
            rows.append(#"{"title":"\#(title)","start":"2026-11-07T\#(String(format: "%02d:%02d", t / 60, t % 60))","duration_minutes":\#(minutes)}"#)
            t += minutes
        }
        let model = QAModel([.reply("Four sprints from now.", [call("c", "create_tasks", #"{"tasks":[\#(rows.joined(separator: ","))]}"#)])])
        let h = QAHarness(store: store, transport: model)
        await h.send(template("sprints"))
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.items.count, 8)
        XCTAssertEqual(p.items.map { $0.after!.category }, [.focus, .rest, .focus, .rest, .focus, .rest, .focus, .rest])
        XCTAssertEqual(p.items.last?.after?.end, TestClock.at(11, 15))
        let flagged = p.items.filter { !$0.notes.isEmpty }
        XCTAssertEqual(flagged.map { $0.after!.title }, ["Thesis ch. 2 — sprint 3"])
        XCTAssertEqual(flagged.first?.notes, ["Overlaps Standup 10:00–10:15"])
    }

    // MARK: 12. Prep for an event — list_tasks(query) → create prep blocks ending at the event

    func testPrepForAnEvent() async throws {
        let mum = task("Call mum", 15, minutes: 30, category: .personal)
        let pitch = task("Client pitch", 16, minutes: 60, category: .meeting)
        let (store, _) = await makeStore([mum, pitch])
        let model = QAModel([
            .reply("", [call("l", "list_tasks", #"{"start":"2026-11-07","end":"2026-11-08","query":"pitch"}"#)]),
            .reply("Prep is ready to review. Rehearse and Print deck clash with Call mum.", [call("c", "create_tasks", #"""
            {"tasks":[
              {"title":"Rehearse pitch","start":"2026-11-07T14:50","duration_minutes":30,"category":"focus"},
              {"title":"Print deck","start":"2026-11-07T15:20","duration_minutes":10,"category":"admin"},
              {"title":"Buffer","start":"2026-11-07T15:30","duration_minutes":10,"category":"rest"},
              {"title":"Travel to pitch","start":"2026-11-07T15:40","duration_minutes":20,"category":"personal"}]}
            """#)]),
        ])
        let h = QAHarness(store: store, transport: model)
        let text = template("prep-event", ["event": "client pitch", "event_time": "16:00"])
        XCTAssertEqual(text, "I have client pitch at 16:00 on today. Add prep blocks before it (rehearse 30m, print deck 10m), 20 min of travel, and a 10-min buffer.")
        await h.send(text)
        XCTAssertEqual(h.toolJSON(1, "l")?["rows"], ["t2|2026-11-07T16:00|60|Client pitch|meeting|upcoming|"])
        let p = try XCTUnwrap(h.proposals.first)
        XCTAssertEqual(p.items.map(\.notes), [["Overlaps Call mum 15:00–15:30"], ["Overlaps Call mum 15:00–15:30"], [], []])
        XCTAssertEqual(p.items.last?.after?.end, pitch.start)
    }
}
