import Foundation
import PlannerCore
import UserNotifications

/// Owns every local notification. Keeps a rolling window under iOS's 64-pending cap and only
/// applies the minimal diff between what should be scheduled and what already is.
@MainActor
final class NotificationScheduler {
    enum Action {
        static let start = "TASK_START"
        static let snooze = "TASK_SNOOZE"
        static let skip = "TASK_SKIP"
        static let complete = "TASK_COMPLETE"
        static let extend = "TASK_EXTEND5"
    }

    static let assistantReadyID = "assistant.ready"
    static let assistantCategory = "ASSISTANT"

    private let center = UNUserNotificationCenter.current()
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var timeSensitiveEnabled = false
    private(set) var lastScheduledCount = 0
    private var resyncTask: Task<Void, Never>?

    private lazy var clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    func registerCategories() {
        let start = UNNotificationAction(identifier: Action.start, title: "Start now", options: [.foreground],
                                         icon: UNNotificationActionIcon(systemImageName: "play.fill"))
        let snooze = UNNotificationAction(identifier: Action.snooze, title: "Snooze 5 min", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath"))
        let skip = UNNotificationAction(identifier: Action.skip, title: "Skip", options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "forward.end"))
        let complete = UNNotificationAction(identifier: Action.complete, title: "Complete", options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let extend = UNNotificationAction(identifier: Action.extend, title: "+5 min", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "plus"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: NotificationSpec.categoryLead, actions: [start, snooze, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationSpec.categoryTimer, actions: [complete, extend], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.assistantCategory, actions: [], intentIdentifiers: []),
        ])
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        timeSensitiveEnabled = settings.timeSensitiveSetting == .enabled
    }

    /// Debounced resync — many edits in a burst produce one diff.
    func scheduleResync(after delay: Duration = .milliseconds(600), _ makeSpecs: @escaping @MainActor () -> [NotificationSpec]) {
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.resync(makeSpecs())
        }
    }

    func specs(store: TaskStore, settings: PlannerSettings, now: Date = Date()) -> [NotificationSpec] {
        var tasks = store.upcoming(from: now, days: NotificationPlanner.horizonDays)
        if let active = store.activeTask { tasks.append(active) }
        let formatter = clockFormatter
        return NotificationPlanner.plan(tasks: tasks, settings: settings, now: now, calendar: store.calendar) { formatter.string(from: $0) }
    }

    func resync(_ desired: [NotificationSpec]) async {
        guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral else { return }
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let diff = NotificationPlanner.diff(
            desired: desired,
            pendingIDs: Set(pending.map(\.identifier)),
            deliveredIDs: Set(delivered.map(\.request.identifier))
        )
        if !diff.removeIDs.isEmpty { center.removePendingNotificationRequests(withIdentifiers: diff.removeIDs) }
        for spec in diff.add {
            try? await center.add(request(for: spec))
        }
        lastScheduledCount = desired.count
    }

    private func request(for spec: NotificationSpec) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = spec.title
        content.body = spec.body
        content.sound = .default
        content.threadIdentifier = spec.threadID
        content.categoryIdentifier = spec.categoryID
        content.userInfo = ["taskID": spec.taskID.uuidString, "kind": spec.kind.rawValue]
        content.interruptionLevel = spec.timeSensitive ? .timeSensitive : .active
        content.relevanceScore = spec.kind == .leadReminder ? 1.0 : 0.6
        let interval = spec.fireDate.timeIntervalSinceNow
        let trigger: UNNotificationTrigger
        if spec.kind == .leadReminder, interval > 90 {
            // Absolute instant: components carry their time zone, so travelling doesn't shift it.
            let comps = Calendar.current.dateComponents(in: TimeZone.current, from: spec.fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        }
        return UNNotificationRequest(identifier: spec.id, content: content, trigger: trigger)
    }

    /// Snooze creates a one-off reminder outside the planner-owned id space.
    func snooze(task: PlanTask, minutes: Int = 5) {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = "Snoozed reminder · \(clockFormatter.string(from: task.start))–\(clockFormatter.string(from: task.end))"
        content.sound = .default
        content.categoryIdentifier = NotificationSpec.categoryLead
        content.threadIdentifier = "day-\(DayKey(task.start))"
        content.userInfo = ["taskID": task.id.uuidString, "kind": "snooze"]
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        center.add(UNNotificationRequest(identifier: "snooze.\(task.id.uuidString)", content: content, trigger: trigger))
    }

    /// A plan edit invalidates a pending snooze for that task.
    func clearSnooze(taskID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: ["snooze.\(taskID.uuidString)"])
    }

    /// Cancels a pending debounced resync (the caller runs one immediately instead).
    func cancelScheduledResync() {
        resyncTask?.cancel()
        resyncTask = nil
    }

    /// Removes delivered + snoozed notifications for a task (it started, finished or was edited).
    func clear(taskID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: ["snooze.\(taskID.uuidString)"])
        Task {
            let delivered = await center.deliveredNotifications()
            let ids = delivered
                .filter { ($0.request.content.userInfo["taskID"] as? String) == taskID.uuidString }
                .map(\.request.identifier)
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    func postAssistantReady(summary: String) {
        let content = UNMutableNotificationContent()
        content.title = "Your plan is ready to review"
        content.body = summary
        content.threadIdentifier = "assistant"
        content.categoryIdentifier = Self.assistantCategory
        content.interruptionLevel = .passive
        content.userInfo = ["deepLink": DeepLink.assistant.absoluteString]
        center.add(UNNotificationRequest(identifier: Self.assistantReadyID, content: content, trigger: nil))
    }
}
