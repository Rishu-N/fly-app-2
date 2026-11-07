import PlannerCore
import SwiftUI

/// Three quick screens, no account: the promise, reminders, and how to start.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                PromisePage().tag(0)
                RemindersPage(onNext: { withAnimation(Motion.glide) { page = 2 } }).tag(1)
                StartPage().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            if page == 0 {
                Button("Continue") { withAnimation(Motion.glide) { page = 1 } }
                    .buttonStyle(PillButtonStyle(fill: palette.now, foreground: palette.onNow))
                    .padding(24)
            }
        }
        .background(palette.bg.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}

private struct PromisePage: View {
    @Environment(\.palette) private var palette
    @State private var started = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Eyebrow("Dayflight", color: palette.now)
            Text("The planner that starts when you do.")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(palette.text1)
            Text("Plan your day minute by minute. When you tap Start, the block's full timer begins — whatever the clock says.")
                .font(.body)
                .foregroundStyle(palette.text2)

            // Tiny demo: 2:00–3:00 started at 1:58 → ends 2:58.
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("Planned")
                    Text("2:00–3:00").font(TypeRamp.timer(30)).foregroundStyle(palette.text2)
                }
                Image(systemName: "arrow.right").foregroundStyle(palette.text3)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(started ? "Started 1:58" : "Tap start", color: palette.now)
                    Text(started ? "ends 2:58" : "60:00")
                        .font(TypeRamp.timer(30))
                        .foregroundStyle(palette.now)
                        .contentTransition(.numericText())
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture { withAnimation(Motion.bouncy) { started.toggle() } }
            .task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(Motion.bouncy) { started = true }
            }
            Spacer()
        }
        .padding(24)
    }
}

private struct RemindersPage: View {
    let onNext: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var settingsStore = model.settings
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "bell.badge.fill").font(.system(size: 44)).foregroundStyle(palette.now)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text("A nudge before each block").font(.system(size: 32, weight: .bold)).foregroundStyle(palette.text1)
            Text("Start, snooze or skip right from the notification. You can change this per block.")
                .foregroundStyle(palette.text2)
            Picker("Lead time", selection: $settingsStore.settings.defaultLeadMinutes) {
                ForEach([1, 2, 5, 10, 15], id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
            Spacer()
            Button("Turn on reminders") {
                Task {
                    await model.notifications.requestAuthorization()
                    onNext()
                }
            }
            .buttonStyle(PillButtonStyle(fill: palette.now, foreground: palette.onNow))
            Button("Not now", action: onNext)
                .frame(maxWidth: .infinity)
                .foregroundStyle(palette.text2)
        }
        .padding(24)
    }
}

private struct StartPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(palette.now)
            Text("Start with a sample day, or a clean slate").font(.system(size: 32, weight: .bold)).foregroundStyle(palette.text1)
            Text("You can connect your OpenAI account later in Settings to plan by chatting. The app works fully without it.")
                .foregroundStyle(palette.text2)
            Spacer()
            Button("Try a sample day") {
                seedSampleDay()
                model.settings.hasOnboarded = true
            }
            .buttonStyle(PillButtonStyle(fill: palette.now, foreground: palette.onNow))
            Button("Start empty") { model.settings.hasOnboarded = true }
                .buttonStyle(PillButtonStyle(fill: palette.surface2, foreground: palette.text1))
        }
        .padding(24)
    }

    private func seedSampleDay() {
        let now = Date()
        var cursor = ScheduleMath.roundUp(now.addingTimeInterval(120), toMinutes: 5)
        let plan: [(String, Int, TaskCategory)] = [
            ("Plan the day", 10, .admin),
            ("Deep work: the big thing", 50, .focus),
            ("Stretch & water", 10, .rest),
            ("Inbox triage", 25, .admin),
            ("Walk", 30, .health),
            ("Read", 25, .learning),
        ]
        var tasks: [PlanTask] = []
        for (title, minutes, category) in plan {
            tasks.append(PlanTask(title: title, start: cursor, durationMinutes: minutes, category: category))
            cursor = cursor.addingTimeInterval(TimeInterval(minutes * 60))
        }
        model.store.apply(ChangeSet(label: "Sample day", upserts: tasks), recordUndo: false)
    }
}
