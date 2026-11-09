import AppIntents
import Foundation
import PlannerCore

// Siri / Shortcuts / Action button / Spotlight. These run in the app process (the system
// launches it in the background when needed) against the real store, then `settle()` so
// notifications, the Live Activity and widgets are correct before the process is suspended.

struct QuickAddBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Block"
    static let description = IntentDescription("Adds a time block from a short phrase like “gym 6:30pm 45m”.")

    @Parameter(title: "Block", requestValueDialog: "What should I add? For example “gym 6:30pm 45m”.")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        await model.store.waitUntilLoaded()
        guard let task = model.quickAdd(text) else {
            return .result(dialog: "I couldn't find what to add in that. Try “gym 6:30pm 45m”.")
        }
        await model.settle()
        return .result(dialog: "Added \(task.title) at \(task.start.clockString()) for \(formatDuration(task.durationMinutes)).")
    }
}

/// Starts the block in focus (due now, or the next one). A `LiveActivityIntent`, so the system
/// lets it start the Live Activity even when the app is in the background.
struct StartNextBlockIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Next Block"
    static let description = IntentDescription("Starts the current or next block's timer for its full planned duration.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        await model.store.waitUntilLoaded()
        let now = Date()
        if let active = model.store.activeTask {
            return .result(dialog: "\(active.title) is already running.")
        }
        guard let task = model.store.snapshot(at: now).focusTask else {
            return .result(dialog: "Nothing left to start today.")
        }
        model.perform(.start, on: task, undoable: false)
        await model.settle()
        let end = model.store.task(task.id)?.session?.projectedEnd(at: now) ?? task.end
        return .result(dialog: "Started \(task.title). \(formatDuration(task.durationMinutes)) on the clock, until \(end.clockString()).")
    }
}

struct CompleteCurrentBlockIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete Current Block"
    static let description = IntentDescription("Marks the running block as done.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        await model.store.waitUntilLoaded()
        guard let active = model.store.activeTask else {
            return .result(dialog: "No block is running.")
        }
        model.perform(.complete, on: active, undoable: false)
        await model.settle()
        if let next = model.store.snapshot(at: Date()).focusTask {
            return .result(dialog: "Done with \(active.title). Next: \(next.title) at \(next.start.clockString()).")
        }
        return .result(dialog: "Done with \(active.title). That's everything for now.")
    }
}

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Next"
    static let description = IntentDescription("Tells you what's running and what's coming up.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        await model.store.waitUntilLoaded()
        let now = Date()
        let snap = model.store.snapshot(at: now)
        var parts: [String] = []
        switch snap.focus {
        case .active(let task):
            if let s = task.session {
                let remaining = s.remaining(at: now)
                parts.append(remaining >= 0
                             ? "\(task.title) has \(formatDuration(Int((remaining / 60).rounded(.up)))) left"
                             : "\(task.title) is \(formatDuration(Int(-remaining / 60))) over time")
            }
        case .due(let task):
            parts.append("\(task.title) is due now")
        case .gap(let next):
            parts.append("You're free until \(next.title) at \(next.start.clockString())")
        case .clear:
            parts.append("Nothing else is planned today")
        }
        if let next = snap.upcoming.first {
            parts.append("then \(next.title) at \(next.start.clockString())")
        }
        return .result(dialog: "\(parts.joined(separator: ", ")).")
    }
}

struct DayflightShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddBlockIntent(),
            phrases: ["Add a block in \(.applicationName)", "Plan something in \(.applicationName)"],
            shortTitle: "Add Block",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: StartNextBlockIntent(),
            phrases: ["Start my next block in \(.applicationName)", "Start next in \(.applicationName)"],
            shortTitle: "Start Next",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: CompleteCurrentBlockIntent(),
            phrases: ["Complete my block in \(.applicationName)", "I'm done in \(.applicationName)"],
            shortTitle: "Complete",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: ["What's next in \(.applicationName)", "What's on in \(.applicationName)"],
            shortTitle: "What's Next",
            systemImageName: "clock"
        )
    }
}
