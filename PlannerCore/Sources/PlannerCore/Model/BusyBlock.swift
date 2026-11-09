import Foundation

/// A read-only busy interval from an external calendar (Apple Calendar via EventKit).
/// Dayflight never writes to external calendars; these only shape free-time math, the day
/// timeline, quick-add slotting and the assistant's view of the day.
public struct BusyBlock: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// 0xRRGGBB of the source calendar, for a subtle tint.
    public var colorHex: UInt32
    public var calendarName: String

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                colorHex: UInt32 = 0x8E8E93, calendarName: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = max(start, end)
        self.isAllDay = isAllDay
        self.colorHex = colorHex
        self.calendarName = calendarName
    }

    public var interval: DateInterval { DateInterval(start: start, end: end) }
    public var durationMinutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

extension ScheduleMath {
    /// Free time that also avoids external calendar events. All-day events are ignored (they
    /// usually mean "holiday"/"birthday", not "busy").
    public static func freeSlots(
        in window: DateInterval,
        tasks: [PlanTask],
        busy: [BusyBlock],
        minimumMinutes: Int = 15,
        now: Date? = nil
    ) -> [DateInterval] {
        let base = freeSlots(in: window, tasks: tasks, minimumMinutes: 1, now: now)
        let blocks = busy.filter { !$0.isAllDay }.map(\.interval).sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for slot in base {
            var pieces = [slot]
            for b in blocks where b.end > slot.start && b.start < slot.end {
                pieces = pieces.flatMap { piece -> [DateInterval] in
                    guard b.end > piece.start, b.start < piece.end else { return [piece] }
                    var out: [DateInterval] = []
                    if b.start > piece.start { out.append(DateInterval(start: piece.start, end: b.start)) }
                    if b.end < piece.end { out.append(DateInterval(start: b.end, end: piece.end)) }
                    return out
                }
            }
            result += pieces
        }
        let minimum = TimeInterval(minimumMinutes) * 60
        return result.filter { $0.duration >= minimum - 0.5 }
    }

    /// Open tasks that overlap an external event (for conflict badges).
    public static func conflicts(tasks: [PlanTask], busy: [BusyBlock]) -> [(PlanTask, BusyBlock)] {
        var out: [(PlanTask, BusyBlock)] = []
        for task in tasks where !task.status.isClosed {
            for b in busy where !b.isAllDay && b.start < task.end && b.end > task.start {
                out.append((task, b))
            }
        }
        return out
    }
}
