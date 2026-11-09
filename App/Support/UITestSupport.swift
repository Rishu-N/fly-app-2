import Foundation
import PlannerCore
import SwiftUI

/// Deterministic, in-memory app state for UI tests and screenshots. Activated only by the
/// `-UITests` launch argument, so it never affects real users.
///
///     -UITests                 sample day with a running task
///     -UITestsScenario <name>  running | paused | overrun | gap | empty
enum UITestSupport {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-UITests") }

    /// `-UITestsDark` forces dark appearance for screenshot runs.
    static var forcedColorScheme: ColorScheme? {
        ProcessInfo.processInfo.arguments.contains("-UITestsDark") ? .dark : nil
    }

    static var scenario: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-UITestsScenario"), i + 1 < args.count else { return "running" }
        return args[i + 1]
    }

    @MainActor
    static func configure(_ settings: SettingsStore) {
        settings.hasOnboarded = true
        var s = settings.settings
        s.remindersEnabled = false            // no permission prompts in tests
        s.liveActivitiesEnabled = false
        s.assistant.consentGiven = true
        settings.settings = s
    }

    static func makePersistence(now: Date = Date()) -> PlannerPersistence {
        InMemoryPersistence(tasks: tasks(scenario: scenario, now: now))
    }

    static func tasks(scenario: String, now: Date) -> [PlanTask] {
        func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
        guard scenario != "empty" else { return [] }

        var done = PlanTask(title: "Inbox triage", start: at(-50), durationMinutes: 25, category: .admin, status: .completed)
        done.session = TimerSession(startedAt: at(-52), targetDuration: 25 * 60, endedAt: at(-30))

        var current = PlanTask(title: "Deep work: launch brief", notes: "Outline, pricing table, FAQ",
                               start: at(-15), durationMinutes: 50, category: .focus)
        current.checklist = [ChecklistItem(title: "Outline", isDone: true), ChecklistItem(title: "Pricing table"), ChecklistItem(title: "FAQ")]
        switch scenario {
        case "gap":
            current.status = .completed
            current.session = TimerSession(startedAt: at(-15), targetDuration: 50 * 60, endedAt: at(-1))
        case "paused":
            current.status = .paused
            current.session = TimerSession(startedAt: at(-17), targetDuration: 50 * 60, pausedAt: at(-2))
        case "overrun":
            current.status = .running
            current.session = TimerSession(startedAt: at(-56), targetDuration: 50 * 60)
        default:
            current.status = .running
            current.session = TimerSession(startedAt: at(-17), targetDuration: 50 * 60)
        }

        let nextStart = scenario == "gap" ? at(40) : at(40)
        return [
            done,
            current,
            PlanTask(title: "Design review", start: nextStart, durationMinutes: 30, category: .meeting),
            PlanTask(title: "Walk", start: at(75), durationMinutes: 20, category: .health),
            PlanTask(title: "Reply to Sam", start: at(100), durationMinutes: 15, category: .social),
            PlanTask(title: "Read: Thinking in Systems", start: at(130), durationMinutes: 30, category: .learning),
        ]
    }
}
