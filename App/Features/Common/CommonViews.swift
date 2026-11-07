import PlannerCore
import SwiftUI

// MARK: - Toast with Undo

struct ToastView: View {
    let toast: AppModel.Toast
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.symbol)
                .foregroundStyle(palette.now)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(palette.text1)
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    withAnimation(Motion.snappy) { model.toast = nil }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.now)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .floatingGlass(in: Capsule())
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Mini player (running timer on other tabs)

struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        if let task = model.store.activeTask, let session = task.session {
            Button {
                model.selectedTab = .now
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(task.category.color).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(palette.text1)
                        Text(task.status == .paused ? "Paused" : "Running")
                            .font(.caption).foregroundStyle(palette.text2)
                    }
                    Spacer(minLength: 8)
                    TimerLabel(session: session, isPaused: task.status == .paused)
                        .font(TypeRamp.timer(22))
                        .foregroundStyle(palette.text1)
                    Button {
                        model.perform(task.status == .paused ? .resume : .pause, on: task)
                    } label: {
                        Image(systemName: task.status == .paused ? "play.fill" : "pause.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.text1)
                    .accessibilityLabel(task.status == .paused ? "Resume" : "Pause")
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .frame(height: 56)
                .floatingGlass(in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Countdown text that costs nothing while running: the system renders `Text(timerInterval:)`.
struct TimerLabel: View {
    let session: TimerSession
    let isPaused: Bool

    var body: some View {
        let now = Date()
        if isPaused {
            Text(formatClock(session.remaining(at: now)))
                .monospacedDigit()
                .opacity(0.6)
        } else if session.isOverrun(at: now) {
            HStack(spacing: 0) {
                Text("+")
                Text(timerInterval: session.projectedEnd(at: now)...Date.distantFuture, countsDown: false)
            }
            .monospacedDigit()
        } else {
            Text(timerInterval: session.displayInterval(at: now), countsDown: true)
                .monospacedDigit()
        }
    }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(fill, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.micro, value: configuration.isPressed)
    }
}

struct CircleButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color
    var size: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .frame(width: size, height: size)
            .foregroundStyle(foreground)
            .background(fill, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.micro, value: configuration.isPressed)
    }
}

// MARK: - Small pieces

struct CategoryDot: View {
    let category: TaskCategory
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(category.color).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Date {
    func clockString() -> String { formatted(date: .omitted, time: .shortened) }
}

extension PlanTask {
    func windowString() -> String { "\(start.clockString())–\(end.clockString())" }
}
