import Foundation

/// A calendar day in the user's local calendar, independent of time zone offsets.
/// Encoded as `"yyyy-MM-dd"` so it is human-readable on disk and cheap to hash.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var monthKey: MonthKey { MonthKey(year: year, month: month) }

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func startDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    public func interval(calendar: Calendar = .current) -> DateInterval {
        let start = startDate(calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        let date = calendar.date(byAdding: .day, value: days, to: startDate(calendar: calendar)) ?? startDate(calendar: calendar)
        return DayKey(date, calendar: calendar)
    }

    /// 1 = Sunday … 7 = Saturday (Gregorian convention, matches `Calendar.component(.weekday)`).
    public func weekday(calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: startDate(calendar: calendar))
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let key = DayKey(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid DayKey \(raw)")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// A calendar month — the persistence partition key.
public struct MonthKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        self.init(year: y, month: m)
    }

    public var description: String { String(format: "%04d-%02d", year, month) }

    public func adding(months: Int) -> MonthKey {
        let zeroBased = (year * 12 + (month - 1)) + months
        return MonthKey(year: zeroBased / 12, month: zeroBased % 12 + 1)
    }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}
