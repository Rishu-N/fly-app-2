import ActivityKit
import AppIntents
import PlannerCore
import SwiftUI
import WidgetKit

/// Lock Screen Live Activity + Dynamic Island (UI-2 §3–4). Every countdown is system-rendered
/// (`Text(timerInterval:)`, `ProgressView(timerInterval:)`), so there are no per-second updates.
/// `staleDate` = projected end, so the overtime view appears without waking the app.
struct TaskLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(context.state.categoryValue.islandColor)
                .widgetURL(DeepLink.now)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale || state.timerEnd <= Date()
            let tint = stale ? Color(hex: 0xFFB547) : state.categoryValue.islandColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ZStack {
                        RingView(state: state, stale: stale, tint: tint, lineWidth: 4)
                        Image(systemName: state.categoryValue.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 44, height: 44)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        CountdownText(state: state, stale: stale)
                            .font(.system(size: 30, weight: .semibold).width(.condensed).monospacedDigit())
                            .foregroundStyle(stale ? tint : .white)
                            .frame(maxWidth: 110, alignment: .trailing)
                        Text(stale ? "over" : (state.isPaused ? "paused" : "ends \(state.timerEnd.formatted(date: .omitted, time: .shortened))"))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(state.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        Text("\(state.categoryValue.displayName) · \(formatDuration(state.plannedMinutes))")
                            .font(.caption2)
                            .foregroundStyle(tint)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        if let next = state.nextTitle, let nextStart = state.nextStart {
                            Text("Next \(nextStart.formatted(date: .omitted, time: .shortened)) · \(next)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        ActivityButtons(state: state, stale: stale, compact: true)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                RingView(state: state, stale: stale, tint: tint, lineWidth: 2.5)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                CountdownText(state: state, stale: stale)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .frame(maxWidth: 52)
            } minimal: {
                RingView(state: state, stale: stale, tint: tint, lineWidth: 2.5)
                    .frame(width: 20, height: 20)
            }
            .keylineTint(tint)
            .widgetURL(DeepLink.now)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenActivityView: View {
    let state: TaskActivityAttributes.ContentState
    let isStale: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        let palette = (DialTheme(rawValue: state.theme) ?? .aurora).palette
        let stale = !state.completed && (isStale || state.timerEnd <= Date()) && !state.isPaused
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Capsule().fill(state.categoryValue.color).frame(width: 4, height: 18)
                Text(state.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(state.completed ? "Done" : (stale ? "Over time" : (state.isPaused ? "Paused" : "until \(state.timerEnd.formatted(date: .omitted, time: .shortened))")))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(stale ? palette.warning : palette.text2)
            }
            HStack(alignment: .center) {
                if state.completed {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(palette.success)
                } else {
                    CountdownText(state: state, stale: stale)
                        .font(.system(size: 44, weight: .semibold).width(.condensed).monospacedDigit())
                        .foregroundStyle(stale ? palette.warning : (state.isPaused ? palette.text2 : palette.text1))
                }
                Spacer()
                if !state.completed {
                    ActivityButtons(state: state, stale: stale, compact: false)
                }
            }
            if !state.completed {
                Group {
                    if state.isPaused || stale {
                        ProgressView(value: stale ? 1 : progressWhilePaused)
                    } else {
                        ProgressView(timerInterval: state.timerStart...state.timerEnd, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                    }
                }
                .tint(stale ? palette.warning : state.categoryValue.color)
            }
            if let next = state.nextTitle, let nextStart = state.nextStart {
                Text("Next \(nextStart.formatted(date: .omitted, time: .shortened)) · \(next)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.text2)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background {
            if !luminanceReduced {
                LinearGradient(colors: DayPhase.at(Date()).stops(dark: scheme == .dark).map { $0.opacity(0.35) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private var progressWhilePaused: Double {
        let total = TimeInterval(state.plannedMinutes * 60)
        guard total > 0, let remaining = state.pausedRemaining else { return 0 }
        return max(0, min(1, 1 - remaining / total))
    }
}

// MARK: - Shared pieces

private struct CountdownText: View {
    let state: TaskActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        if state.isPaused {
            Text(formatClock(state.pausedRemaining ?? 0))
        } else if stale {
            // Counts up from the projected end.
            Text(state.timerEnd, style: .timer)
        } else {
            Text(timerInterval: state.timerStart...state.timerEnd, countsDown: true)
        }
    }
}

private struct RingView: View {
    let state: TaskActivityAttributes.ContentState
    let stale: Bool
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        if state.isPaused || stale {
            ZStack {
                Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
                Circle().trim(from: 0, to: stale ? 1 : pausedFraction)
                    .stroke(tint.opacity(state.isPaused ? 0.6 : 1), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if state.isPaused {
                    Image(systemName: "pause.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(tint)
                }
            }
        } else {
            ProgressView(timerInterval: state.timerStart...state.timerEnd, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(tint)
        }
    }

    private var pausedFraction: CGFloat {
        let total = TimeInterval(state.plannedMinutes * 60)
        guard total > 0, let remaining = state.pausedRemaining else { return 0 }
        return CGFloat(max(0, min(1, remaining / total)))
    }
}

private struct ActivityButtons: View {
    let state: TaskActivityAttributes.ContentState
    let stale: Bool
    let compact: Bool

    var body: some View {
        let size: CGFloat = compact ? 36 : 44
        HStack(spacing: compact ? 10 : 16) {
            if stale {
                Button(intent: ExtendTaskIntent(taskID: state.taskID)) {
                    Text("+5").font(.system(size: 15, weight: .bold)).frame(width: size, height: size)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.16), in: Circle())
            } else {
                Button(intent: TogglePauseTaskIntent(taskID: state.taskID)) {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: size, height: size)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.16), in: Circle())
            }
            Button(intent: CompleteTaskIntent(taskID: state.taskID)) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: size, height: size)
            }
            .buttonStyle(.plain)
            .background(state.categoryValue.islandColor, in: Circle())
        }
    }
}
