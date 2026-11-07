import Foundation

/// User-initiated timer/lifecycle actions.
public enum TaskAction: Equatable, Sendable {
    case start
    case pause
    case resume
    case complete
    case cancel
    case skip
    case extend(minutes: Int)
    /// Put a finished/skipped/cancelled task back to planned.
    case reopen
}

public enum TransitionError: Error, Equatable, Sendable {
    case notAllowed(from: TaskStatus, action: String)
    /// Only one task may be active; the caller must resolve the other one first.
    case anotherTaskActive(UUID)
}

/// Pure state machine for a single task. The store enforces cross-task rules (single active).
///
///     planned ──start──▶ running ◀──resume── paused
///        │                 │  └──pause──────▲
///        │skip/complete    │complete/cancel/extend
///        ▼                 ▼
///     skipped/completed  completed/cancelled ──reopen──▶ planned
public enum TaskTransitions {
    public static func apply(_ action: TaskAction, to task: PlanTask, at now: Date) throws -> PlanTask {
        var t = task
        switch (action, task.status) {
        case (.start, .planned):
            // Timer runs for the PLANNED duration from the moment of starting.
            t.session = TimerSession(startedAt: now, targetDuration: task.duration)
            t.status = .running

        case (.pause, .running):
            t.session?.pause(at: now)
            t.status = .paused

        case (.resume, .paused):
            t.session?.resume(at: now)
            t.status = .running

        case (.complete, .running), (.complete, .paused):
            t.session?.end(at: now)
            t.status = .completed

        case (.complete, .planned):
            // "Mark done" without timing it.
            t.status = .completed

        case (.cancel, .running), (.cancel, .paused):
            t.session?.end(at: now)
            t.status = .cancelled

        case (.cancel, .planned), (.skip, .planned):
            t.status = .skipped

        case (.extend(let minutes), .running), (.extend(let minutes), .paused):
            t.session?.extend(by: TimeInterval(max(1, minutes)) * 60, at: now)

        case (.reopen, .completed), (.reopen, .cancelled), (.reopen, .skipped):
            t.status = .planned
            t.session = nil

        default:
            throw TransitionError.notAllowed(from: task.status, action: String(describing: action))
        }
        t.updatedAt = now
        return t
    }

    /// Which actions the UI should offer for a task right now.
    public static func availableActions(for task: PlanTask) -> [TaskAction] {
        switch task.status {
        case .planned: [.start, .complete, .skip]
        case .running: [.pause, .complete, .cancel, .extend(minutes: 5)]
        case .paused: [.resume, .complete, .cancel, .extend(minutes: 5)]
        case .completed, .cancelled, .skipped: [.reopen]
        }
    }
}
