import EventKit
import Foundation
import Observation
import PlannerCore
import UIKit

/// Read-only Apple Calendar overlay. Events are shown as busy time on the timeline, avoided by
/// quick-add slotting and visible to the assistant (titles only if the user allows it).
/// Dayflight never writes to the user's calendars.
///
/// Cost: one EventKit predicate fetch per visible day, cached until the event store changes.
@MainActor
@Observable
final class CalendarOverlay {
    private(set) var status: EKAuthorizationStatus
    /// Bumped when the cache is invalidated (calendar edited elsewhere, access changed).
    private(set) var revision = 0

    var enabled: Bool {
        didSet {
            AppGroup.defaults.set(enabled, forKey: Self.enabledKey)
            invalidate()
        }
    }

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var cache: [DayKey: [BusyBlock]] = [:]
    @ObservationIgnored private static let enabledKey = "calendar.overlay.enabled"

    init() {
        status = EKEventStore.authorizationStatus(for: .event)
        enabled = AppGroup.defaults.bool(forKey: Self.enabledKey)
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }
    }

    var isAuthorized: Bool { status == .fullAccess }
    var isActive: Bool { enabled && isAuthorized }

    /// Asks for read access (iOS 17+ full access is required to read events).
    @discardableResult
    func requestAccess() async -> Bool {
        let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        status = EKEventStore.authorizationStatus(for: .event)
        if granted { enabled = true }
        invalidate()
        return granted
    }

    func invalidate() {
        cache.removeAll()
        revision &+= 1
    }

    /// Events on one day (timed + all-day), sorted.
    func events(on day: DayKey, calendar: Calendar) -> [BusyBlock] {
        _ = revision
        guard isActive else { return [] }
        if let cached = cache[day] { return cached }
        let interval = day.interval(calendar: calendar)
        let predicate = eventStore.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        let blocks = eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { event -> BusyBlock in
                BusyBlock(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Busy",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    colorHex: Self.hex(event.calendar?.cgColor),
                    calendarName: event.calendar?.title ?? ""
                )
            }
            .sorted { $0.start < $1.start }
        cache[day] = blocks
        return blocks
    }

    /// Events overlapping an interval (spanning days).
    func events(in interval: DateInterval, calendar: Calendar) -> [BusyBlock] {
        guard isActive else { return [] }
        var day = DayKey(interval.start, calendar: calendar)
        let last = DayKey(interval.end, calendar: calendar)
        var seen = Set<String>()
        var result: [BusyBlock] = []
        while day <= last {
            for e in events(on: day, calendar: calendar) where e.end > interval.start && e.start < interval.end && !seen.contains(e.id) {
                seen.insert(e.id)
                result.append(e)
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    private static func hex(_ cgColor: CGColor?) -> UInt32 {
        guard let cgColor else { return 0x8E8E93 }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(cgColor: cgColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return (c(r) << 16) | (c(g) << 8) | c(b)
    }
}
