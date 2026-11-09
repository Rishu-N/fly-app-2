import Foundation
import Observation
import PlannerCore
import SwiftUI
import UIKit
import UserNotifications

/// Composition root. Owns the store and every side-effect service, and fans out store changes:
///
/// - timer actions → Live Activity immediately, notification resync (150 ms debounce)
/// - schedule edits → notification resync (600 ms debounce), widget snapshot (1 s debounce)
/// - background entry points (Lock Screen buttons, notification actions, going to background)
///   call `settle()`, which skips the debounces and *awaits* disk, Live Activity, notifications
///   and widgets inside a background assertion — so nothing stale fires after suspension.
/// - a single "boundary" timer re-renders Home exactly when the focus can change.
@MainActor
@Observable
final class AppModel: NSObject {
    static let shared = AppModel()

    enum AppTab: Hashable { case now, plan, assistant }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var symbol: String
        var undo: (@MainActor () -> Void)?
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    struct StartConflict: Identifiable {
        let id = UUID()
        let requested: PlanTask
        let active: PlanTask
    }

    // Services
    let store: TaskStore
    let settings: SettingsStore
    let notifications = NotificationScheduler()
    let liveActivities = LiveActivityController()
    let widgets = WidgetSnapshotWriter()
    /// Read-only Apple Calendar events (busy time). Off until the user enables it.
    let calendarOverlay = CalendarOverlay()

    /// Created on first use (Assistant tab / Settings) — never on a background launch.
    var assistantService: AssistantService {
        if let existing = _assistant { return existing }
        let created = AssistantService(store: store, settingsStore: settings, notifications: notifications)
        _assistant = created
        return created
    }
    @ObservationIgnored private var _assistant: AssistantService?

    // UI state
    var selectedTab: AppTab = .now
    var showCapture = false
    var captureSeed = ""
    var editingTask: PlanTask?
    var showSettings = false
    var showInsights = false
    var toast: Toast?
    var startConflict: StartConflict?
    var selectedPlanDay = DayKey(Date())
    /// Bumped at schedule boundaries so views that derive state from the clock re-evaluate.
    private(set) var clockTick = Date()

    /// App-level bootstrap (store load + Live Activity adoption + notification permission).
    /// Background entry points await this, not just the store, so `settle()` can see them.
    @ObservationIgnored private var bootTask: Task<Void, Never>?
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var liveActivityTask: Task<Void, Never>?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var lastActiveID: UUID?
    @ObservationIgnored private var lastKnownToday = DayKey(Date())

    private override init() {
        // Cheap: no disk IO here (the store loads asynchronously in `bootstrap`).
        let persistence: PlannerPersistence = UITestSupport.isActive
            ? UITestSupport.makePersistence()
            : JSONFilePersistence(directory: AppGroup.dataDirectory)
        store = TaskStore(persistence: persistence)
        settings = SettingsStore()
        super.init()
        if UITestSupport.isActive { UITestSupport.configure(settings) }
        Haptics.enabled = settings.settings.hapticsEnabled

        store.onChange = { [weak self] change in self?.storeDidChange(change) }
        settings.onChange = { [weak self] old, new in self?.settingsDidChange(old: old, new: new) }
        UNUserNotificationCenter.current().delegate = self
        notifications.registerCategories()

        let nc = NotificationCenter.default
        nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dayChanged() }
        }
        nc.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.timeZoneChanged() }
        }
        nc.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dayChanged() }
        }

        bootTask = Task { await bootstrap() }
    }

    private func bootstrap() async {
        await store.bootstrap()
        liveActivities.adoptExisting()
        await notifications.refreshAuthorization()
        lastActiveID = store.activeTask?.id
        syncSideEffects(urgent: true)
        armBoundaryTimer()
    }

    // MARK: Scene lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isActive = true
            clockTick = Date()
            guard store.isLoaded else { return } // bootstrap will sync when it finishes
            store.materializeRecurrences()
            store.autoCompleteIfNeeded(now: Date(), enabled: settings.settings.autoCompleteWhenTimerEnds)
            Task {
                await notifications.refreshAuthorization()
                syncSideEffects(urgent: true)
            }
            armBoundaryTimer()
        case .background:
            isActive = false
            boundaryTask?.cancel()
            Task { await settleInBackground(name: "enter-background") }
        default:
            break
        }
    }

    private func dayChanged() {
        guard store.isLoaded else { return }
        store.materializeRecurrences()
        clockTick = Date()
        let today = DayKey(Date(), calendar: store.calendar)
        // Follow "today" only if the user was looking at the old today (not browsing elsewhere).
        if selectedPlanDay == lastKnownToday { selectedPlanDay = today }
        lastKnownToday = today
        syncSideEffects(urgent: false)
    }

    private func timeZoneChanged() {
        store.setCalendar(.current)
        dayChanged()
    }

    // MARK: Change fan-out

    private func storeDidChange(_ change: StoreChange) {
        switch change.kind {
        case .timer(let action):
            for id in change.taskIDs { notifications.clear(taskID: id) }
            syncSideEffects(urgent: true)
            if case .start = action { Haptics.play(.start) }
        case .schedule:
            for id in change.taskIDs { notifications.clearSnooze(taskID: id) }
            syncSideEffects(urgent: false)
        case .reload:
            syncSideEffects(urgent: false)
        }
        clockTick = Date()
        armBoundaryTimer()
    }

    private func settingsDidChange(old: PlannerSettings, new: PlannerSettings) {
        Haptics.enabled = new.hapticsEnabled
        syncSideEffects(urgent: false)
    }

    /// Debounced fan-out for foreground changes.
    private func syncSideEffects(urgent: Bool) {
        guard store.isLoaded else { return }
        liveActivityTask?.cancel()
        liveActivityTask = Task { [weak self] in await self?.syncLiveActivity() }
        notifications.scheduleResync(after: urgent ? .milliseconds(150) : .milliseconds(600)) { [weak self] in
            guard let self else { return [] }
            return self.notifications.specs(store: self.store, settings: self.settings.settings)
        }
        widgets.scheduleWrite { [weak self] in
            self?.makeWidgetSnapshot() ?? WidgetSnapshot(generatedAt: Date(), tasks: [], theme: "aurora", defaultLeadMinutes: 5)
        }
    }

    private func syncLiveActivity() async {
        let now = Date()
        let active = store.activeTask
        let next = active.flatMap { a in store.snapshot(at: now).upcoming.first(where: { $0.id != a.id }) }
        let ended = lastActiveID.flatMap { id in id == active?.id ? nil : store.task(id) }
        lastActiveID = active?.id
        await liveActivities.sync(active: active, next: next, enabled: settings.settings.liveActivitiesEnabled,
                                  theme: settings.theme.rawValue, endedTask: ended)
    }

    /// Runs every side effect *now* and waits for all of them.
    func settle() async {
        guard store.isLoaded else { return }
        notifications.cancelScheduledResync()
        widgets.cancelScheduledWrite()
        liveActivityTask?.cancel()
        await store.flushNow()
        await syncLiveActivity()
        await notifications.resync(notifications.specs(store: store, settings: settings.settings))
        await widgets.write(makeWidgetSnapshot())
    }

    /// `settle()` wrapped in a background-task assertion (with an expiration handler), for
    /// intents, notification actions and entering the background.
    func settleInBackground(name: String) async {
        let assertion = BackgroundAssertion(name: name)
        await settle()
        assertion.end()
    }

    private func makeWidgetSnapshot() -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(),
            tasks: store.tasksAround(Date()),
            theme: settings.theme.rawValue,
            defaultLeadMinutes: settings.settings.defaultLeadMinutes
        )
    }

    /// One sleeping task wakes exactly at the next moment the Home focus can change
    /// (window opens/closes, lead time begins, timer hits zero). While the app is in the
    /// foreground it also wakes once a minute so relative labels ("in 12m") stay right;
    /// in the background nothing runs at all.
    private func armBoundaryTimer() {
        boundaryTask?.cancel()
        guard isActive, store.isLoaded else { return }
        let now = Date()
        let tasks = store.tasksAround(now)
        let lead = settings.settings.defaultLeadMinutes
        var wake = now.addingTimeInterval(60)
        if let b = ScheduleEngine.nextBoundary(after: now, tasks: tasks), b < wake { wake = b }
        for t in tasks where t.status == .planned {
            let ready = t.start.addingTimeInterval(-TimeInterval((t.leadTimeMinutes ?? lead) * 60))
            if ready > now, ready < wake { wake = ready }
        }
        let delay = max(0.05, wake.timeIntervalSince(now) + 0.05)
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.store.autoCompleteIfNeeded(now: Date(), enabled: self.settings.settings.autoCompleteWhenTimerEnds)
            if let active = self.store.activeTask, let s = active.session, active.status == .running,
               abs(s.projectedEnd(at: Date()).timeIntervalSinceNow) < 1.5 {
                Haptics.play(.warning)
            }
            self.clockTick = Date()
            self.armBoundaryTimer()
        }
    }

    // MARK: Task actions (all UI + intents + notification actions go through here)

    func start(_ task: PlanTask) {
        if let active = store.activeTask, active.id != task.id {
            startConflict = StartConflict(requested: task, active: active)
            return
        }
        perform(.start, on: task)
    }

    func resolveConflict(_ resolution: ActiveConflictResolution?) {
        guard let conflict = startConflict else { return }
        startConflict = nil
        guard let resolution else { return }
        do {
            try store.perform(.start, on: conflict.requested.id, resolving: resolution)
            let entry = store.lastUndoID
            withAnimation(Motion.conveyor) { clockTick = Date() }
            showToast("Started \(conflict.requested.title)", symbol: "play.fill") { [weak self] in
                if let entry { self?.store.undo(entry) }
            }
        } catch {
            showToast("Couldn't start that task", symbol: "exclamationmark.triangle")
        }
    }

    func perform(_ action: TaskAction, on task: PlanTask, undoable: Bool = true) {
        let previousUndo = store.lastUndoID
        do {
            try store.perform(action, on: task.id)
        } catch {
            return
        }
        // `perform` records one undo entry for complete / cancel / skip; the toast undoes *that*.
        let entry = store.lastUndoID != previousUndo ? store.lastUndoID : nil
        let undo: (@MainActor () -> Void)? = (undoable && entry != nil) ? { [weak self] in
            if let entry { self?.store.undo(entry) }
        } : nil
        switch action {
        case .complete:
            Haptics.play(.complete)
            if undoable { showToast("Completed \(task.title)", symbol: "checkmark.circle.fill", undo: undo) }
        case .cancel:
            Haptics.play(.cancel)
            if undoable { showToast("Cancelled \(task.title)", symbol: "xmark.circle", undo: undo) }
        case .skip:
            Haptics.play(.cancel)
            if undoable { showToast("Skipped \(task.title)", symbol: "forward.end", undo: undo) }
        case .pause, .resume:
            Haptics.play(.pause)
        case .extend:
            Haptics.play(.tap)
        default:
            break
        }
    }

    func delete(_ task: PlanTask) {
        guard let removed = store.delete(task.id) else { return }
        let entry = store.lastUndoID
        Haptics.play(.cancel)
        showToast("Deleted \(removed.title)", symbol: "trash") { [weak self] in
            if let entry { self?.store.undo(entry) }
        }
    }

    /// Applies a change set with an Undo toast bound to exactly that change.
    func applyWithUndo(_ changes: ChangeSet, toast message: String, symbol: String) {
        store.apply(changes)
        let entry = store.lastUndoID
        showToast(message, symbol: symbol) { [weak self] in
            if let entry { self?.store.undo(entry) }
        }
    }

    func shiftRest(after task: PlanTask, minutes: Int) {
        let n = store.shiftRemaining(from: task.start, byMinutes: minutes)
        guard n > 0 else { return }
        let entry = store.lastUndoID
        showToast("Moved \(n) task\(n == 1 ? "" : "s") by \(minutes) min", symbol: "arrow.down.to.line") { [weak self] in
            if let entry { self?.store.undo(entry) }
        }
    }

    /// Quick capture: parse locally, fill smart defaults, add, offer Undo.
    @discardableResult
    func quickAdd(_ text: String, on day: DayKey? = nil) -> PlanTask? {
        let now = Date()
        let parsed = QuickAddParser(calendar: store.calendar).parse(text, now: now)
        guard !parsed.title.isEmpty else { return nil }
        let duration = parsed.durationMinutes ?? lastDuration(forTitle: parsed.title) ?? settings.settings.defaultDurationMinutes
        let start = parsed.start ?? nextFreeStart(duration: duration, on: day ?? DayKey(now, calendar: store.calendar), now: now)
        let task = PlanTask(
            title: parsed.title,
            start: start,
            durationMinutes: duration,
            category: parsed.category ?? TaskCategory.guess(fromTitle: parsed.title),
            source: .quickAdd
        )
        store.add(task)
        Haptics.play(.tap)
        showToast("Added \(task.title) · \(task.start.clockString())", symbol: "plus.circle.fill") { [weak self] in
            _ = self?.store.delete(task.id, undoLabel: nil)
        }
        return task
    }

    func nextFreeStart(duration: Int, on day: DayKey, now: Date) -> Date {
        let cal = store.calendar
        let dayInterval = day.interval(calendar: cal)
        let windowStart = cal.date(bySettingHour: settings.settings.dayStartHour, minute: 0, second: 0, of: dayInterval.start) ?? dayInterval.start
        let windowEnd = cal.date(bySettingHour: min(23, settings.settings.dayEndHour), minute: 0, second: 0, of: dayInterval.start) ?? dayInterval.end
        let lower = max(windowStart, ScheduleMath.roundUp(now, toMinutes: 5, calendar: cal))
        let window = DateInterval(start: min(lower, windowEnd), end: max(lower, windowEnd))
        let busy = calendarOverlay.events(in: window, calendar: cal)
        let free = ScheduleMath.freeSlots(in: window, tasks: store.tasks(in: window), busy: busy, minimumMinutes: duration, now: now)
        if let slot = free.first { return ScheduleMath.roundUp(slot.start, toMinutes: 5, calendar: cal) }
        return lower
    }

    private func lastDuration(forTitle title: String) -> Int? {
        let key = title.lowercased()
        return store.tasksByID.values
            .filter { $0.title.lowercased() == key }
            .max(by: { $0.createdAt < $1.createdAt })?
            .durationMinutes
    }

    func showToast(_ message: String, symbol: String, undo: (@MainActor () -> Void)? = nil) {
        withAnimation(Motion.snappy) { toast = Toast(message: message, symbol: symbol, undo: undo) }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.snappy) { self?.toast = nil }
        }
    }

    // MARK: Intents (Live Activity buttons)

    func handleIntent(_ action: TimerIntentAction, taskID: String) async {
        let assertion = BackgroundAssertion(name: "intent")
        defer { assertion.end() }
        await store.waitUntilLoaded()
        await bootTask?.value // existing Live Activity adopted, notification permission known
        // Validate against the task's *current* state (the Live Activity may be stale).
        guard let id = UUID(uuidString: taskID), let task = store.task(id), task.status.isActive else {
            await settle()
            return
        }
        switch action {
        case .togglePause:
            perform(task.status == .paused ? .resume : .pause, on: task, undoable: false)
        case .complete:
            perform(.complete, on: task, undoable: false)
        case .extend:
            perform(.extend(minutes: 5), on: task, undoable: false)
        }
        await settle()
    }

    // MARK: Deep links

    func open(_ url: URL) {
        guard url.scheme == DeepLink.scheme else { return }
        switch url.host {
        case "plan": selectedTab = .plan
        case "assistant": selectedTab = .assistant
        case "task":
            selectedTab = .now
            if let id = UUID(uuidString: url.lastPathComponent), let task = store.task(id), !task.status.isActive {
                editingTask = task
            }
        default: selectedTab = .now
        }
    }
}

// MARK: - Notification delegate

extension AppModel: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Don't shout a reminder at someone already looking at Now.
        let onNow = await MainActor.run { AppModel.shared.selectedTab == .now }
        return onNow ? [.list] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let taskID = (info["taskID"] as? String).flatMap(UUID.init(uuidString:))
        let deepLink = (info["deepLink"] as? String).flatMap(URL.init(string:))
        await AppModel.shared.handleNotificationAction(action, taskID: taskID, deepLink: deepLink)
    }

    func handleNotificationAction(_ action: String, taskID: UUID?, deepLink: URL?) async {
        let assertion = BackgroundAssertion(name: "notification-action")
        defer { assertion.end() }
        await store.waitUntilLoaded()
        await bootTask?.value // existing Live Activity adopted, notification permission known
        if let deepLink { open(deepLink); return }
        guard let taskID, let task = store.task(taskID) else { return }
        // Every action is checked against the task's current state.
        switch action {
        case NotificationScheduler.Action.start where task.status == .planned:
            selectedTab = .now
            start(task)
        case NotificationScheduler.Action.snooze where task.status == .planned:
            await notifications.snooze(task: task)
        case NotificationScheduler.Action.skip where task.status == .planned:
            perform(.skip, on: task, undoable: false)
        case NotificationScheduler.Action.complete where task.status.isActive:
            perform(.complete, on: task, undoable: false)
        case NotificationScheduler.Action.extend where task.status.isActive:
            perform(.extend(minutes: 5), on: task, undoable: false)
        default:
            // Tapped the notification itself (or the action no longer applies).
            selectedTab = .now
        }
        await settle()
    }
}

/// `UIApplication.beginBackgroundTask` with a guaranteed end (expiration handler + `end()`).
@MainActor
final class BackgroundAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
