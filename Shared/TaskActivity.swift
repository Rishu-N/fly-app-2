import ActivityKit
import AppIntents
import Foundation
import PlannerCore

/// Live Activity schema. The content state is tiny and only changes on user actions —
/// the countdown itself is rendered by the system from `timerStart...timerEnd`.
struct TaskActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var taskID: String
        var title: String
        var category: String
        var plannedStart: Date
        var plannedMinutes: Int
        /// Lower bound for `Text(timerInterval:)` / `ProgressView(timerInterval:)` (start + paused time).
        var timerStart: Date
        /// Projected end of the timer (moves later after pauses / +5).
        var timerEnd: Date
        /// Non-nil while paused: frozen remaining seconds.
        var pausedRemaining: TimeInterval?
        var nextTitle: String?
        var nextStart: Date?
        var theme: String
        /// Final "Done" state shown briefly after completion.
        var completed: Bool = false

        var isPaused: Bool { pausedRemaining != nil && !completed }
        var categoryValue: TaskCategory { TaskCategory(rawValue: category) ?? .focus }
        var taskUUID: UUID? { UUID(uuidString: taskID) }
    }

    /// Static for the activity's lifetime.
    var startedAt: Date
}

extension TaskActivityAttributes.ContentState {
    init(task: PlanTask, next: PlanTask?, theme: String, now: Date = Date()) {
        let session = task.session ?? TimerSession(startedAt: now, targetDuration: task.duration)
        // Built only from stored timestamps, so the state is identical whenever it's rebuilt while
        // paused (cheap equality de-dupe, no needless Live Activity updates).
        let range = session.displayInterval(at: now)
        let pausedRemaining = session.pausedAt.map { max(0, session.remaining(at: $0)) }
        self.init(
            taskID: task.id.uuidString,
            title: task.title,
            category: task.category.rawValue,
            plannedStart: task.start,
            plannedMinutes: task.durationMinutes,
            timerStart: range.lowerBound,
            timerEnd: range.upperBound,
            pausedRemaining: session.isPaused ? pausedRemaining : nil,
            nextTitle: next?.title,
            nextStart: next?.start,
            theme: theme,
            completed: false
        )
    }
}

// MARK: - Lock Screen / Dynamic Island buttons
//
// `LiveActivityIntent.perform()` runs in the APP process (the system launches it in the
// background if needed), so the app target handles the action against the real store.
// In the widget extension these compile to no-ops.

enum TimerIntentAction: String, Sendable {
    case togglePause, complete, extend
}

struct TogglePauseTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Task"
    static let description = IntentDescription("Pauses or resumes the running task timer.")

    @Parameter(title: "Task ID") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        #if DAYFLIGHT_APP
        await AppModel.shared.handleIntent(.togglePause, taskID: taskID)
        #endif
        return .result()
    }
}

struct CompleteTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Marks the running task as done.")

    @Parameter(title: "Task ID") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        #if DAYFLIGHT_APP
        await AppModel.shared.handleIntent(.complete, taskID: taskID)
        #endif
        return .result()
    }
}

struct ExtendTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 5 Minutes"
    static let description = IntentDescription("Adds five minutes to the running task timer.")

    @Parameter(title: "Task ID") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        #if DAYFLIGHT_APP
        await AppModel.shared.handleIntent(.extend, taskID: taskID)
        #endif
        return .result()
    }
}
