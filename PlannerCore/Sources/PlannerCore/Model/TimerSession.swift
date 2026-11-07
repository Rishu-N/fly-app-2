import Foundation

/// What actually happened once the user pressed Start.
///
/// The timer is *derived from timestamps*, never from ticking counters, so it is exact after
/// the app is suspended, killed or the phone reboots, and costs zero CPU while running.
///
///     elapsed   = (endedAt ?? pausedAt ?? now) − startedAt − pausedTotal
///     remaining = targetDuration − elapsed            (negative ⇒ overrun)
///     projected end (running) = startedAt + pausedTotal + targetDuration
public struct TimerSession: Codable, Hashable, Sendable {
    public var startedAt: Date
    /// Planned duration at the moment of starting, plus any "+5 min" extensions.
    public var targetDuration: TimeInterval
    /// Non-nil while paused.
    public var pausedAt: Date?
    /// Sum of completed pause intervals.
    public var pausedTotal: TimeInterval
    public var endedAt: Date?
    /// Number of times the user extended the timer.
    public var extensions: Int

    public init(
        startedAt: Date,
        targetDuration: TimeInterval,
        pausedAt: Date? = nil,
        pausedTotal: TimeInterval = 0,
        endedAt: Date? = nil,
        extensions: Int = 0
    ) {
        self.startedAt = startedAt
        self.targetDuration = max(60, targetDuration)
        self.pausedAt = pausedAt
        self.pausedTotal = max(0, pausedTotal)
        self.endedAt = endedAt
        self.extensions = extensions
    }

    public var isPaused: Bool { pausedAt != nil && endedAt == nil }
    public var isEnded: Bool { endedAt != nil }

    /// Total paused time including an in-progress pause.
    public func pausedDuration(at now: Date) -> TimeInterval {
        var total = pausedTotal
        if let pausedAt, endedAt == nil { total += max(0, now.timeIntervalSince(pausedAt)) }
        return total
    }

    public func elapsed(at now: Date) -> TimeInterval {
        let reference = endedAt ?? pausedAt ?? now
        let paused = pausedTotal
        return max(0, reference.timeIntervalSince(startedAt) - paused)
    }

    /// Negative when overrunning.
    public func remaining(at now: Date) -> TimeInterval {
        targetDuration - elapsed(at: now)
    }

    public func progress(at now: Date) -> Double {
        guard targetDuration > 0 else { return 1 }
        return min(1, max(0, elapsed(at: now) / targetDuration))
    }

    public func isOverrun(at now: Date) -> Bool { remaining(at: now) < 0 }

    /// Wall-clock moment the timer reaches zero. While paused this slides forward with `now`.
    public func projectedEnd(at now: Date) -> Date {
        if let endedAt { return endedAt }
        if pausedAt != nil { return now.addingTimeInterval(max(0, remaining(at: now))) }
        return startedAt.addingTimeInterval(pausedTotal + targetDuration)
    }

    /// The `start...end` range to feed `Text(timerInterval:)` / `ProgressView(timerInterval:)`
    /// so the system renders the countdown without any app-driven updates.
    /// The lower bound is shifted by paused time so progress views stay correct.
    /// Uses completed pauses only, so the range is identical at any `now` while paused (pair it
    /// with `pauseTime: pausedAt` or a static label while paused).
    public func displayInterval(at now: Date) -> ClosedRange<Date> {
        let lower = startedAt.addingTimeInterval(pausedTotal)
        let upper = max(lower, lower.addingTimeInterval(targetDuration))
        return lower...upper
    }

    // MARK: Mutations

    public mutating func pause(at now: Date) {
        guard pausedAt == nil, endedAt == nil else { return }
        pausedAt = now
    }

    public mutating func resume(at now: Date) {
        guard let pausedAt, endedAt == nil else { return }
        pausedTotal += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    /// Adds time. In overtime, "+5" means five more minutes *from now* (overtime is absorbed
    /// into the target), not five minutes off the debt.
    public mutating func extend(by seconds: TimeInterval, at now: Date) {
        guard endedAt == nil, seconds > 0 else { return }
        if remaining(at: now) < 0 {
            targetDuration = elapsed(at: now) + seconds
        } else {
            targetDuration += seconds
        }
        extensions += 1
    }

    public mutating func end(at now: Date) {
        guard endedAt == nil else { return }
        if let pausedAt {
            pausedTotal += max(0, now.timeIntervalSince(pausedAt))
            self.pausedAt = nil
        }
        endedAt = max(now, startedAt)
    }
}
