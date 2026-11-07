import ActivityKit
import Foundation
import PlannerCore

/// Mirrors the single active task into one Live Activity. Updates are sent only when the
/// content state actually changes (start / pause / resume / extend / next-task change), never
/// on a clock — the system renders the countdown.
@MainActor
final class LiveActivityController {
    private var current: Activity<TaskActivityAttributes>?
    private var lastState: TaskActivityAttributes.ContentState?
    /// The user swiped this task's activity away — don't re-request it on every foreground.
    private var dismissedTaskID: String?

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Adopt an activity that survived an app relaunch.
    func adoptExisting() {
        let all = Activity<TaskActivityAttributes>.activities
        current = all.first(where: { $0.activityState == .active || $0.activityState == .stale })
        lastState = current?.content.state
        // End duplicates (shouldn't happen, but never leave orphans on the Lock Screen).
        for extra in all where extra.id != current?.id {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Reconciles the Live Activity with the store. Awaitable so background entry points can be
    /// sure the Lock Screen is correct before the process is suspended.
    func sync(active: PlanTask?, next: PlanTask?, enabled: Bool, theme: String, endedTask: PlanTask? = nil) async {
        guard enabled, let active, active.status.isActive else {
            await endCurrent(finished: endedTask)
            return
        }
        let state = TaskActivityAttributes.ContentState(task: active, next: next, theme: theme)
        if let current, current.content.state.taskID == state.taskID, current.activityState == .dismissed {
            dismissedTaskID = state.taskID
            self.current = nil
            lastState = nil
        }
        guard dismissedTaskID != state.taskID else { return }
        let stale: Date? = state.isPaused ? nil : state.timerEnd
        let content = ActivityContent(state: state, staleDate: stale, relevanceScore: 100)

        if let current, current.content.state.taskID == state.taskID,
           current.activityState == .active || current.activityState == .stale {
            guard state != lastState else { return }
            lastState = state
            await current.update(content)
            return
        }

        await endCurrent(finished: nil)
        // Another sync may have started an activity while we awaited the old one's end;
        // requesting again would orphan one on the Lock Screen.
        guard current == nil else { return }
        guard isAvailable else { return }
        // ActivityKit caps a Live Activity at 8 h; don't start one for a timer that can't finish.
        guard state.timerEnd.timeIntervalSinceNow < 8 * 3600 else { return }
        do {
            current = try Activity.request(
                attributes: TaskActivityAttributes(startedAt: active.session?.startedAt ?? Date()),
                content: content,
                pushType: nil
            )
            lastState = state
        } catch {
            // Typically "app is not foreground" when started from a notification action;
            // `sync` runs again when the app becomes active.
            current = nil
            lastState = nil
        }
    }

    private func endCurrent(finished task: PlanTask?) async {
        guard let activity = current else { return }
        current = nil
        lastState = nil
        if task?.status == .completed {
            // Leave a brief "Done" card on the Lock Screen.
            var state = activity.content.state
            state.completed = true
            state.pausedRemaining = 0
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(120)))
        } else {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
