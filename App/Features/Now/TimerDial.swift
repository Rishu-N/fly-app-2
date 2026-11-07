import PlannerCore
import SwiftUI

/// Bezel ring with 60 static ticks + condensed monospaced digits.
///
/// Rendering cost: the tick ring is a static `Canvas` drawn once; only the progress arc and the
/// digits live inside a 1 Hz `TimelineView`, which SwiftUI stops when the view is off-screen or
/// the app is in the background. No shadows or blurs on anything that moves.
struct TimerDial: View {
    enum Mode: Equatable {
        case running(TimerSession)
        case paused(TimerSession)
        /// Not started: shows what *will* run.
        case preview(minutes: Int)
        /// Free time until the next block.
        case countdown(to: Date, total: TimeInterval)
    }

    let mode: Mode
    var category: TaskCategory = .focus
    @Binding var showEndsAt: Bool

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 64

    private let ringWidth: CGFloat = 10

    var body: some View {
        Group {
            switch mode {
            case .running, .countdown:
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    dial(at: context.date)
                }
            case .paused, .preview:
                dial(at: Date())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(at: Date()))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityHint("Double-tap to switch between time left and end time")
    }

    @ViewBuilder
    private func dial(at now: Date) -> some View {
        let state = DialState(mode: mode, now: now, palette: palette, category: category)
        let digitsOnly = typeSize.isAccessibilitySize
        ZStack {
            if !digitsOnly {
                TickRing()
                    .foregroundStyle(palette.text3.opacity(0.45))
                    .padding(2)
                Circle()
                    .stroke(palette.ringTrack, lineWidth: ringWidth)
                    .padding(16)
                Circle()
                    .trim(from: 0, to: state.remainingFraction)
                    .stroke(state.ringColor, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(x: -1, y: 1) // drains clockwise like a watch hand
                    .padding(16)
                    // No implicit animation: a 1 s tween per 1 Hz tick would render every frame.
                if state.overrunFraction > 0 {
                    Circle()
                        .trim(from: 0, to: state.overrunFraction)
                        .stroke(palette.warning, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(32)
                }
            }
            VStack(spacing: 4) {
                Eyebrow(state.eyebrow, color: state.eyebrowColor)
                Text(showEndsAt ? state.endsAtText : state.digits)
                    .font(TypeRamp.timer(state.digits.count > 5 ? digitSize * 0.8 : digitSize))
                    .tracking(-1)
                    .foregroundStyle(state.digitColor)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.micro, value: state.digits)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(showEndsAt ? state.digits : state.caption)
                    .font(TypeRamp.timeLabel)
                    .foregroundStyle(palette.text2)
                    .lineLimit(1)
            }
            .padding(.horizontal, digitsOnly ? 0 : 36)
        }
        .aspectRatio(digitsOnly ? nil : 1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Motion.snappy) { showEndsAt.toggle() }
        }
    }

    private func accessibilityText(at now: Date) -> String {
        let s = DialState(mode: mode, now: now, palette: palette, category: category)
        return "\(s.eyebrow). \(s.spokenRemaining). \(s.caption)"
    }
}

/// Pure presentation math for the dial (no views).
private struct DialState {
    var remainingFraction: CGFloat = 1
    var overrunFraction: CGFloat = 0
    var digits = "0:00"
    var caption = ""
    var endsAtText = ""
    var eyebrow = ""
    var spokenRemaining = ""
    var ringColor: Color
    var digitColor: Color
    var eyebrowColor: Color

    init(mode: TimerDial.Mode, now: Date, palette: Palette, category: TaskCategory) {
        ringColor = palette.now
        digitColor = palette.text1
        eyebrowColor = palette.text2
        switch mode {
        case .running(let session):
            let remaining = session.remaining(at: now)
            let end = session.projectedEnd(at: now)
            remainingFraction = CGFloat(max(0, min(1, remaining / session.targetDuration)))
            endsAtText = end.clockString()
            if remaining < 0 {
                digits = formatClock(remaining)
                eyebrow = "Over time"
                eyebrowColor = palette.warning
                ringColor = palette.warning
                digitColor = palette.warning
                overrunFraction = CGFloat(min(1, -remaining / 3600))
                caption = "planned \(formatDuration(Int(session.targetDuration / 60)))"
                spokenRemaining = "\(Int(-remaining / 60)) minutes over time"
            } else {
                digits = formatClock(remaining.rounded(.up))
                eyebrow = "Ends \(end.clockString())"
                caption = "started \(session.startedAt.clockString())"
                if remaining <= 300 {
                    ringColor = palette.warning
                    eyebrowColor = palette.warning
                }
                spokenRemaining = "\(Int((remaining / 60).rounded(.up))) minutes left of \(Int(session.targetDuration / 60)), ends \(end.clockString())"
            }
        case .paused(let session):
            let remaining = max(0, session.remaining(at: now))
            remainingFraction = CGFloat(remaining / session.targetDuration)
            digits = formatClock(remaining)
            digitColor = palette.text2
            ringColor = palette.text3
            eyebrow = "Paused"
            caption = session.pausedAt.map { "since \($0.clockString())" } ?? ""
            endsAtText = now.addingTimeInterval(remaining).clockString()
            spokenRemaining = "Paused with \(Int(remaining / 60)) minutes left"
        case .preview(let minutes):
            digits = formatClock(TimeInterval(minutes * 60))
            let end = now.addingTimeInterval(TimeInterval(minutes * 60))
            eyebrow = "Ready"
            eyebrowColor = palette.now
            caption = "Full \(formatDuration(minutes)) · ends \(end.clockString())"
            endsAtText = end.clockString()
            ringColor = palette.now.opacity(0.35)
            spokenRemaining = "\(minutes) minute timer, ends \(end.clockString()) if you start now"
        case .countdown(let target, let total):
            let remaining = max(0, target.timeIntervalSince(now))
            remainingFraction = CGFloat(total > 0 ? remaining / total : 0)
            digits = formatClock(remaining.rounded(.up))
            eyebrow = "Free"
            caption = "until \(target.clockString())"
            endsAtText = target.clockString()
            ringColor = palette.text3
            spokenRemaining = "\(Int(remaining / 60)) minutes free"
        }
    }
}

/// 60 ticks, every 5th longer — drawn once.
private struct TickRing: View {
    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<60 {
                let angle = Double(i) / 60 * 2 * .pi
                let long = i % 5 == 0
                let inner = r - (long ? 9 : 5)
                var path = Path()
                path.move(to: CGPoint(x: center.x + inner * sin(angle), y: center.y - inner * cos(angle)))
                path.addLine(to: CGPoint(x: center.x + r * sin(angle), y: center.y - r * cos(angle)))
                context.stroke(path, with: .foreground, lineWidth: long ? 1.5 : 1)
            }
        }
        .accessibilityHidden(true)
    }
}
