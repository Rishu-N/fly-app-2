import Foundation

/// Result of parsing a one-line quick-add such as `"Gym 6:30pm 45m #health"`.
public struct QuickAddResult: Equatable, Sendable {
    public var title: String
    public var start: Date?
    public var durationMinutes: Int?
    public var category: TaskCategory?
    /// Human-readable pieces that were recognised, for the confirmation chips under the field.
    public var chips: [Chip]

    public enum Chip: Equatable, Sendable {
        case day(String)
        case time(Date)
        case duration(Int)
        case category(TaskCategory)
    }
}

/// Fast, fully local natural-language parser for quick capture. Handles:
///
/// - times: `6`, `6:30`, `6pm`, `6:30 pm`, `18:00`, `noon`, `midnight`, `at 6`, `@6`
/// - ranges: `2-3pm`, `14:00-15:30`, `2pm-3:30pm`, `2 to 3pm`, `from 9 to 11`
/// - durations: `45m`, `45 min`, `1h`, `1.5h`, `1h30`, `1h30m`, `90 minutes`, `for 2 hours`
/// - days: `today`, `tonight`, `tomorrow`/`tmr`/`tmrw`, weekday names (`mon`, `friday`, `next tue`)
/// - category: `#health`, `#gym`, `#meeting` (falls back to a guess from the title)
///
/// A bare hour without am/pm resolves to the next upcoming occurrence today (`gym 6:30` at 13:00 → 18:30).
public struct QuickAddParser: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(_ input: String, now: Date) -> QuickAddResult {
        var tokens = input
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map { String($0) }
        // Split "2pm-3pm" style is handled inside token parsing; split a lone "-" range marker.
        tokens = tokens.flatMap { token -> [String] in
            if token != "-", token.hasSuffix("-") { return [String(token.dropLast()), "-"] }
            if token != "-", token.hasPrefix("-"), token.count > 1, token.dropFirst().first?.isNumber == true { return ["-", String(token.dropFirst())] }
            return [token]
        }

        var consumed = Set<Int>()
        var dayOffset: Int?
        var dayLabel: String?
        var startClock: Clock?
        var endClock: Clock?
        var duration: Int?
        var category: TaskCategory?

        var i = 0
        while i < tokens.count {
            let raw = tokens[i]
            let lower = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))
            let next = i + 1 < tokens.count ? tokens[i + 1].lowercased() : nil

            // Category hashtag
            if lower.hasPrefix("#"), lower.count > 1 {
                if let c = TaskCategory(loose: String(lower.dropFirst())) {
                    category = c
                    consumed.insert(i)
                }
                i += 1
                continue
            }

            // Day words
            if dayOffset == nil, let (offset, label) = dayWord(lower, next: next, now: now) {
                dayOffset = offset.offset
                dayLabel = label
                consumed.insert(i)
                if offset.usedNext { consumed.insert(i + 1); i += 1 }
                if lower == "tonight", startClock == nil { startClock = nil }
                i += 1
                continue
            }

            // Connectors that only make sense before a time / duration.
            if ["at", "@", "from", "by"].contains(lower), let next, Self.parseClockToken(next, following: nil) != nil || Self.rangeParts(next) != nil {
                consumed.insert(i)
                i += 1
                continue
            }
            if lower == "for", let next, Self.parseDurationToken(next) != nil || Double(next) != nil {
                consumed.insert(i)
                i += 1
                continue
            }

            // Duration (one or two tokens)
            if duration == nil {
                if let d = Self.parseDurationToken(lower) {
                    duration = d
                    consumed.insert(i)
                    i += 1
                    continue
                }
                if let value = Double(lower), let next, let unit = Self.durationUnitMultiplier(next) {
                    duration = Int((value * unit).rounded())
                    consumed.insert(i); consumed.insert(i + 1)
                    i += 2
                    continue
                }
            }

            // Range in one token: "2-3pm", "14:00-15:30"
            if startClock == nil, let (a, b) = Self.rangeParts(lower),
               var s = Self.parseClockToken(a, following: nil), var e = Self.parseClockToken(b, following: nil) {
                Self.reconcileRange(&s, &e)
                startClock = s; endClock = e
                consumed.insert(i)
                i += 1
                continue
            }

            // Time (with optional separate meridiem token), maybe followed by "-"/"to" + end time.
            // A bare number ("3") only counts as a time in a time-like context, so
            // "answer 3 emails" keeps its number.
            if startClock == nil, var s = Self.parseClockToken(lower, following: next),
               !s.isBare || bareNumberLooksLikeTime(previous: i > 0 ? tokens[i - 1].lowercased() : nil, next: next, afterNext: i + 2 < tokens.count ? tokens[i + 2].lowercased() : nil) {
                consumed.insert(i)
                var advance = 1
                if s.meridiemConsumedNext { consumed.insert(i + 1); advance = 2 }
                // Range continuation
                let j = i + advance
                if j + 1 < tokens.count, ["-", "to", "until", "till"].contains(tokens[j].lowercased()) {
                    let afterNext = j + 2 < tokens.count ? tokens[j + 2].lowercased() : nil
                    if var e = Self.parseClockToken(tokens[j + 1].lowercased(), following: afterNext) {
                        Self.reconcileRange(&s, &e)
                        endClock = e
                        consumed.insert(j); consumed.insert(j + 1)
                        advance += 2
                        if e.meridiemConsumedNext { consumed.insert(j + 2); advance += 1 }
                    }
                }
                startClock = s
                i += advance
                continue
            }

            i += 1
        }

        // Resolve dates
        let today = calendar.startOfDay(for: now)
        let baseDay = calendar.date(byAdding: .day, value: dayOffset ?? 0, to: today) ?? today
        var chips: [QuickAddResult.Chip] = []
        if let dayLabel { chips.append(.day(dayLabel)) }

        var start: Date?
        if let startClock {
            start = resolve(startClock, on: baseDay, now: now, preferFuture: dayOffset == nil)
        }
        if let s = start, let endClock, let startClock {
            var e = calendar.date(bySettingHour: endClock.hour24(defaultingFrom: startClock), minute: endClock.minute, second: 0, of: calendar.startOfDay(for: s)) ?? s
            if e <= s { e = calendar.date(byAdding: .day, value: 1, to: e) ?? e }
            duration = max(1, Int((e.timeIntervalSince(s) / 60).rounded()))
        }
        if let start { chips.append(.time(start)) }
        if let duration { chips.append(.duration(duration)) }
        if let category { chips.append(.category(category)) }

        var titleTokens: [String] = []
        for (index, token) in tokens.enumerated() where !consumed.contains(index) {
            titleTokens.append(token)
        }
        // Trim dangling connectors.
        while let last = titleTokens.last, ["at", "for", "on", "from", "-", "to", "@"].contains(last.lowercased()) {
            titleTokens.removeLast()
        }
        var title = titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = title.first, first.isLowercase { title = first.uppercased() + title.dropFirst() }

        return QuickAddResult(title: title, start: start, durationMinutes: duration, category: category, chips: chips)
    }

    // MARK: - Clock parsing

    struct Clock: Equatable {
        var hour: Int        // as written (1–12 when meridiem given, 0–23 otherwise)
        var minute: Int
        var meridiem: Meridiem?
        /// Written as 24h (e.g. "18:00", "06:30") — never reinterpret.
        var explicit24h: Bool
        var meridiemConsumedNext: Bool = false
        /// Plain integer with no colon or am/pm ("9").
        var isBare: Bool = false

        enum Meridiem { case am, pm }

        func hour24(defaultingFrom other: Clock? = nil) -> Int {
            let m = meridiem ?? (explicit24h ? nil : other?.meridiem)
            switch m {
            case .am: return hour % 12
            case .pm: return hour % 12 + 12
            case nil: return hour
            }
        }
    }

    static func parseClockToken(_ rawToken: String, following next: String?) -> Clock? {
        var token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))
        if token.hasPrefix("@") { token.removeFirst() }
        switch token {
        case "noon", "midday": return Clock(hour: 12, minute: 0, meridiem: .pm, explicit24h: true)
        case "midnight": return Clock(hour: 0, minute: 0, meridiem: nil, explicit24h: true)
        default: break
        }

        var meridiem: Clock.Meridiem?
        for (suffix, value) in [("am", Clock.Meridiem.am), ("a.m.", .am), ("a", .am), ("pm", .pm), ("p.m.", .pm), ("p", .pm)] {
            if token.hasSuffix(suffix), token.count > suffix.count {
                let stem = token.dropLast(suffix.count)
                if stem.last?.isNumber == true { meridiem = value; token = String(stem); break }
            }
        }
        var consumedNext = false
        if meridiem == nil, let next {
            let n = next.trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))
            if ["am", "a.m"].contains(n) || n == "a.m." { meridiem = .am; consumedNext = true }
            if ["pm", "p.m"].contains(n) || n == "p.m." { meridiem = .pm; consumedNext = true }
        }

        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        guard let h = Int(parts[0]) else { return nil }
        let m = parts.count == 2 ? Int(parts[1]) ?? -1 : 0
        guard (0...59).contains(m) else { return nil }
        if parts.count == 2, parts[1].count != 2 { return nil }

        if let meridiem {
            guard (1...12).contains(h) else { return nil }
            return Clock(hour: h, minute: m, meridiem: meridiem, explicit24h: false, meridiemConsumedNext: consumedNext)
        }
        // A bare number with no colon is only a time when it looks like an hour (avoid "3 emails").
        if parts.count == 1 {
            guard (0...23).contains(h), parts[0].count <= 2 else { return nil }
            if let next, durationUnitMultiplier(next) != nil { return nil } // "3 hours"
        }
        guard (0...23).contains(h) else { return nil }
        let explicit24 = h >= 13 || h == 0 || (parts[0].count == 2 && parts[0].first == "0")
        return Clock(hour: h, minute: m, meridiem: nil, explicit24h: explicit24, isBare: parts.count == 1)
    }

    private func bareNumberLooksLikeTime(previous: String?, next: String?, afterNext: String?) -> Bool {
        if let previous, ["at", "@", "from", "by", "-", "to", "until", "till"].contains(previous) { return true }
        guard let next else { return true }
        if ["-", "to", "until", "till", "for", "on", "today", "tonight", "tomorrow", "tmr", "tmrw"].contains(next) { return true }
        if next.hasPrefix("#") || Self.parseDurationToken(next) != nil || Self.weekdayIndex(next) != nil { return true }
        if Double(next) != nil, let afterNext, Self.durationUnitMultiplier(afterNext) != nil { return true }
        return false
    }

    static func rangeParts(_ token: String) -> (String, String)? {
        let pieces = token.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2, !pieces[0].isEmpty, !pieces[1].isEmpty,
              pieces[0].first?.isNumber == true, pieces[1].first?.isNumber == true else { return nil }
        return (String(pieces[0]), String(pieces[1]))
    }

    /// "2-3pm" → 2pm–3pm, "11-1pm" → 11am–1pm, "9-11" (no meridiem) stays ambiguous for `resolve`.
    static func reconcileRange(_ start: inout Clock, _ end: inout Clock) {
        if start.meridiem == nil, !start.explicit24h, let em = end.meridiem {
            let endH = end.hour24()
            let candidate = Clock(hour: start.hour, minute: start.minute, meridiem: em, explicit24h: false)
            if candidate.hour24() <= endH {
                start = candidate
            } else {
                start = Clock(hour: start.hour, minute: start.minute, meridiem: em == .pm ? .am : .pm, explicit24h: false)
            }
        }
        if end.meridiem == nil, !end.explicit24h, let sm = start.meridiem {
            var candidate = Clock(hour: end.hour, minute: end.minute, meridiem: sm, explicit24h: false)
            if candidate.hour24() <= start.hour24() { candidate.meridiem = (sm == .am ? .pm : .am) }
            end = candidate
        }
    }

    // MARK: - Durations

    static func durationUnitMultiplier(_ rawUnit: String) -> Double? {
        let unit = rawUnit.trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))
        switch unit {
        case "m", "min", "mins", "minute", "minutes": return 1
        case "h", "hr", "hrs", "hour", "hours": return 60
        default: return nil
        }
    }

    /// "45m", "45min", "1h", "1.5h", "1h30", "1h30m", "90minutes", "2hrs".
    static func parseDurationToken(_ rawToken: String) -> Int? {
        let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))
        guard let first = token.first, first.isNumber else { return nil }
        // h+m compound
        if let hIndex = token.firstIndex(where: { $0 == "h" }) {
            let hoursPart = token[token.startIndex..<hIndex]
            var rest = token[token.index(after: hIndex)...]
            for unit in ["ours", "our", "rs", "r"] where rest.hasPrefix(unit) {
                rest = rest.dropFirst(unit.count)
                break
            }
            guard let hours = Double(hoursPart) else { return nil }
            if rest.isEmpty { return Int((hours * 60).rounded()) }
            var minutesPart = rest
            for unit in ["minutes", "minute", "mins", "min", "m"] where minutesPart.hasSuffix(unit) {
                minutesPart = minutesPart.dropLast(unit.count)
                break
            }
            guard let minutes = Int(minutesPart), (0..<60).contains(minutes) else { return nil }
            return Int((hours * 60).rounded()) + minutes
        }
        for unit in ["minutes", "minute", "mins", "min", "m"] where token.hasSuffix(unit) {
            let number = token.dropLast(unit.count)
            guard let value = Double(number), value > 0 else { return nil }
            return Int(value.rounded())
        }
        return nil
    }

    // MARK: - Days

    private struct DayOffset { var offset: Int; var usedNext: Bool }

    private func dayWord(_ word: String, next: String?, now: Date) -> (DayOffset, String)? {
        switch word {
        case "today": return (DayOffset(offset: 0, usedNext: false), "Today")
        case "tonight": return (DayOffset(offset: 0, usedNext: false), "Tonight")
        case "tomorrow", "tmr", "tmrw", "tomorow": return (DayOffset(offset: 1, usedNext: false), "Tomorrow")
        default: break
        }
        var usedNext = false
        var candidate = word
        if word == "next" || word == "on", let next, Self.weekdayIndex(next) != nil {
            candidate = next
            usedNext = true
        }
        guard let target = Self.weekdayIndex(candidate) else { return nil }
        let todayWeekday = calendar.component(.weekday, from: now)
        var delta = (target - todayWeekday + 7) % 7
        if delta == 0 { delta = 7 } // "monday" on a Monday means next week
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (DayOffset(offset: delta, usedNext: usedNext), names[target - 1])
    }

    static func weekdayIndex(_ word: String) -> Int? {
        let w = word.trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))
        let table: [(Int, [String])] = [
            (1, ["sun", "sunday"]), (2, ["mon", "monday"]), (3, ["tue", "tues", "tuesday"]),
            (4, ["wed", "weds", "wednesday"]), (5, ["thu", "thur", "thurs", "thursday"]),
            (6, ["fri", "friday"]), (7, ["sat", "saturday"]),
        ]
        return table.first(where: { $0.1.contains(w) })?.0
    }

    // MARK: - Resolution

    private func resolve(_ clock: Clock, on day: Date, now: Date, preferFuture: Bool) -> Date {
        func at(_ hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: clock.minute, second: 0, of: day) ?? day
        }
        if clock.meridiem != nil || clock.explicit24h { return at(clock.hour24()) }
        // Ambiguous 1–12: choose the next upcoming of h / h+12 when the day is today.
        let morning = at(clock.hour % 12 == 0 && clock.hour == 12 ? 12 : clock.hour)
        guard clock.hour <= 12 else { return morning }
        let evening = at(clock.hour == 12 ? 0 : clock.hour + 12)
        if !preferFuture {
            // Another day: assume daytime hours (7–12 morning, 1–6 afternoon/evening).
            return (1...6).contains(clock.hour) ? evening : morning
        }
        let grace: TimeInterval = 15 * 60
        if morning.addingTimeInterval(grace) >= now { return morning }
        if clock.hour != 12, evening.addingTimeInterval(grace) >= now { return evening }
        return clock.hour == 12 ? morning : evening
    }
}
