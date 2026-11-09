import PlannerCore
import SwiftUI

/// The magnified "now" slab: the current task becomes a live control surface.
struct LensCard: View {
    let snapshot: NowSnapshot
    let now: Date
    let leadMinutes: Int
    let namespace: Namespace.ID

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEndsAt = false
    @State private var dragX: CGFloat = 0
    @State private var showLater = false
    @State private var completeTrigger = 0

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .top)
            .background {
                ZStack {
                    palette.surface
                    AuroraField(tone: tone, enabled: model.settings.settings.ambientBackground)
                        .opacity(0.9)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(palette.separator.opacity(0.6), lineWidth: 0.5))
            .background(alignment: .leading) { swipeHint }
            .offset(x: dragX)
            .simultaneousGesture(swipe)
            .matchedGeometryEffect(id: snapshot.focusTask?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, in: namespace)
            .sensoryFeedback(.success, trigger: completeTrigger)
            .confirmationDialog("Later", isPresented: $showLater, titleVisibility: .hidden) { laterActions }
    }

    // MARK: Content by state

    @ViewBuilder
    private var content: some View {
        switch snapshot.focus {
        case .active(let task):
            activeContent(task)
        case .due(let task):
            plannedContent(task, label: lateLabel(task), labelColor: now.timeIntervalSince(task.start) > 60 ? palette.warning : palette.now)
        case .gap(let next):
            let untilStart = next.start.timeIntervalSince(now)
            let lead = TimeInterval((next.leadTimeMinutes ?? leadMinutes) * 60)
            if untilStart <= max(lead, 60) {
                plannedContent(next, label: "Starts \(next.start.clockString())", labelColor: palette.now)
            } else {
                gapContent(next)
            }
        case .clear:
            clearContent
        }
    }

    private func header(_ task: PlanTask, label: String, labelColor: Color) -> some View {
        HStack(spacing: 8) {
            CategoryDot(category: task.category, size: 10)
            Text(task.windowString())
                .font(TypeRamp.timeLabel)
                .foregroundStyle(palette.text2)
            Spacer()
            Eyebrow(label, color: labelColor)
        }
    }

    private func titleBlock(_ task: PlanTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(TypeRamp.cardTitle)
                .foregroundStyle(palette.text1)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !task.checklist.isEmpty {
                ChecklistPreview(task: task)
            } else if !task.notes.isEmpty {
                Text(task.notes)
                    .font(.subheadline)
                    .foregroundStyle(palette.text2)
                    .lineLimit(2)
            }
        }
    }

    private func activeContent(_ task: PlanTask) -> some View {
        let session = task.session ?? TimerSession(startedAt: now, targetDuration: task.duration)
        let paused = task.status == .paused
        let overrun = !paused && session.isOverrun(at: now)
        return VStack(alignment: .leading, spacing: 16) {
            header(task, label: paused ? "Paused" : (overrun ? "Over time" : "Now"), labelColor: overrun ? palette.warning : palette.now)
            titleBlock(task)
            TimerDial(mode: paused ? .paused(session) : .running(session), category: task.category, showEndsAt: $showEndsAt)
                .frame(maxWidth: 250)
                .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                if overrun {
                    Button("+5") { act(.extend(minutes: 5), task) }
                        .buttonStyle(CircleButtonStyle(fill: palette.surface2, foreground: palette.text1))
                        .accessibilityLabel("Add 5 minutes")
                    Button("+15") { act(.extend(minutes: 15), task) }
                        .buttonStyle(CircleButtonStyle(fill: palette.surface2, foreground: palette.text1))
                        .accessibilityLabel("Add 15 minutes")
                } else {
                    Button {
                        act(paused ? .resume : .pause, task)
                    } label: {
                        Image(systemName: paused ? "play.fill" : "pause.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(CircleButtonStyle(fill: palette.surface2, foreground: palette.text1))
                    .accessibilityLabel(paused ? "Resume" : "Pause")
                }
                Button {
                    complete(task)
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .buttonStyle(PillButtonStyle(fill: palette.success, foreground: .white))
                .contextMenu {
                    if let next = snapshot.upcoming.first {
                        Button("Complete & start \(next.title)", systemImage: "forward.fill") {
                            completeTrigger += 1
                            withAnimation(Motion.adaptive(Motion.conveyor, reduceMotion: reduceMotion)) {
                                model.completeAndStartNext(task)
                            }
                        }
                    }
                    Button("Complete", systemImage: "checkmark") { complete(task) }
                }
                .accessibilityAction(named: "Complete and start next") { model.completeAndStartNext(task) }
                Menu {
                    if !overrun {
                        Button("Add 5 minutes", systemImage: "plus") { act(.extend(minutes: 5), task) }
                    }
                    Button("Edit", systemImage: "pencil") { model.editingTask = task }
                    Button("Cancel task", systemImage: "xmark", role: .destructive) { act(.cancel, task) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 56)
                        .foregroundStyle(palette.text2)
                }
                .accessibilityLabel("More actions")
            }
        }
    }

    private func plannedContent(_ task: PlanTask, label: String, labelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(task, label: label, labelColor: labelColor)
            titleBlock(task)
            TimerDial(mode: .preview(minutes: task.durationMinutes), category: task.category, showEndsAt: $showEndsAt)
                .frame(maxWidth: 250)
                .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                Button {
                    withAnimation(Motion.adaptive(Motion.bouncy, reduceMotion: reduceMotion)) { model.start(task) }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(PillButtonStyle(fill: palette.now, foreground: palette.onNow))
                .sensoryFeedback(.impact(weight: .medium), trigger: task.status)
                Button {
                    act(.skip, task)
                } label: {
                    Image(systemName: "forward.end")
                }
                .buttonStyle(CircleButtonStyle(fill: palette.surface2, foreground: palette.text1))
                .accessibilityLabel("Skip")
                Menu {
                    Button("Mark done", systemImage: "checkmark") { complete(task) }
                    Button("Edit", systemImage: "pencil") { model.editingTask = task }
                    Button("Delete", systemImage: "trash", role: .destructive) { model.delete(task) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 56)
                        .foregroundStyle(palette.text2)
                }
                .accessibilityLabel("More actions")
            }
        }
    }

    private func gapContent(_ next: PlanTask) -> some View {
        let total = max(60, next.start.timeIntervalSince(snapshot.previous?.expectedEnd(at: now) ?? now))
        let freeMinutes = Int(next.start.timeIntervalSince(now) / 60)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Eyebrow("Free time", color: palette.text2)
                Spacer()
                Text("Next · \(next.start.clockString())")
                    .font(TypeRamp.timeLabel)
                    .foregroundStyle(palette.text2)
            }
            Text("Until \(next.title)")
                .font(TypeRamp.cardTitle)
                .foregroundStyle(palette.text1)
                .lineLimit(2)
            TimerDial(mode: .countdown(to: next.start, total: total), category: next.category, showEndsAt: $showEndsAt)
                .frame(maxWidth: 250)
                .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                Button {
                    withAnimation(Motion.bouncy) { model.start(next) }
                } label: {
                    Label("Start \(next.title) now", systemImage: "play.fill")
                        .lineLimit(1)
                }
                .buttonStyle(PillButtonStyle(fill: palette.now, foreground: palette.onNow))
                Button {
                    model.captureSeed = "\(max(5, freeMinutes))m"
                    model.showCapture = true
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(CircleButtonStyle(fill: palette.surface2, foreground: palette.text1))
                .accessibilityLabel("Fill the gap")
            }
        }
    }

    @ViewBuilder
    private var clearContent: some View {
        let today = model.store.tasks(on: DayKey(now, calendar: model.store.calendar))
        let done = today.filter { $0.status == .completed }
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(today.isEmpty ? "Your day is open" : "End of day", color: palette.text2)
            if today.isEmpty {
                Text("Plan a block and the timer starts when you do.")
                    .font(TypeRamp.cardTitle)
                    .foregroundStyle(palette.text1)
                Text("Try “deep work 9:30 90m” or “gym 6pm 45m”.")
                    .font(.subheadline)
                    .foregroundStyle(palette.text2)
            } else {
                let focused = done.compactMap { $0.session?.elapsed(at: now) }.reduce(0, +)
                Text("Done \(done.count)/\(today.count)")
                    .font(TypeRamp.timer(56))
                    .foregroundStyle(palette.text1)
                Text("Focused \(formatDuration(Int(focused / 60))) today")
                    .font(.subheadline)
                    .foregroundStyle(palette.text2)
            }
            Spacer(minLength: 12)
            HStack(spacing: 12) {
                Button {
                    model.captureSeed = ""
                    model.showCapture = true
                } label: {
                    Label("Add block", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle(fill: palette.now, foreground: palette.onNow))
                Button {
                    model.selectedTab = .assistant
                } label: {
                    Label(today.isEmpty ? "Plan with AI" : "Plan tomorrow", systemImage: "sparkles")
                }
                .buttonStyle(PillButtonStyle(fill: palette.surface2, foreground: palette.text1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Gestures

    private var activeTask: PlanTask? {
        if case .active(let t) = snapshot.focus { return t }
        return nil
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                guard snapshot.focusTask != nil else { return }
                dragX = value.translation.width * 0.6
            }
            .onEnded { value in
                let w = value.translation.width
                let fast = value.predictedEndTranslation.width
                defer { withAnimation(Motion.glide) { dragX = 0 } }
                if let task = activeTask, w > 120 || fast > 600 {
                    complete(task)
                } else if snapshot.focusTask != nil, w < -120 || fast < -600 {
                    showLater = true
                }
            }
    }

    @ViewBuilder
    private var swipeHint: some View {
        if dragX > 20, activeTask != nil {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(palette.success)
                .padding(.leading, 12)
                .opacity(Double(min(1, dragX / 80)))
        }
    }

    @ViewBuilder
    private var laterActions: some View {
        if let task = snapshot.focusTask {
            if task.status.isActive {
                Button("Add 5 minutes") { act(.extend(minutes: 5), task) }
                Button("Add 15 minutes") { act(.extend(minutes: 15), task) }
                Button("Cancel task", role: .destructive) { act(.cancel, task) }
            } else {
                Button("Move to next free slot") {
                    var moved = task
                    moved.start = model.nextFreeStart(duration: task.durationMinutes, on: DayKey(now, calendar: model.store.calendar), now: now.addingTimeInterval(TimeInterval(task.durationMinutes * 60)))
                    model.applyWithUndo(ChangeSet(label: "Moved \(task.title)", upserts: [moved]),
                                        toast: "Moved to \(moved.start.clockString())", symbol: "arrow.right")
                }
                Button("Move to tomorrow") {
                    var moved = task
                    moved.start = model.store.calendar.date(byAdding: .day, value: 1, to: task.start) ?? task.start
                    model.applyWithUndo(ChangeSet(label: "Moved \(task.title)", upserts: [moved]),
                                        toast: "Moved to tomorrow", symbol: "arrow.right")
                }
                Button("Skip") { act(.skip, task) }
            }
        }
    }

    // MARK: Actions

    private func act(_ action: TaskAction, _ task: PlanTask) {
        withAnimation(Motion.adaptive(Motion.conveyor, reduceMotion: reduceMotion)) {
            model.perform(action, on: task)
        }
    }

    private func complete(_ task: PlanTask) {
        completeTrigger += 1
        act(.complete, task)
    }

    private var tone: AuroraField.Tone {
        switch snapshot.focus {
        case .active(let task):
            guard let s = task.session else { return .normal }
            if task.status == .paused { return .paused }
            let remaining = s.remaining(at: now)
            if remaining < 0 { return .overrun }
            if remaining <= 300 { return .endingSoon }
            return .normal
        case .due, .gap: return .normal
        case .clear: return .idle
        }
    }

    private func lateLabel(_ task: PlanTask) -> String {
        let late = Int(now.timeIntervalSince(task.start) / 60)
        return late >= 1 ? "Late \(late)m" : "Now"
    }
}

/// Up to three checklist items, checkable in place.
private struct ChecklistPreview: View {
    let task: PlanTask
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(task.checklist.prefix(3)) { item in
                Button {
                    var updated = task
                    if let i = updated.checklist.firstIndex(where: { $0.id == item.id }) {
                        updated.checklist[i].isDone.toggle()
                        model.store.update(updated)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isDone ? palette.success : palette.text3)
                            .contentTransition(.symbolEffect(.replace))
                        Text(item.title)
                            .strikethrough(item.isDone)
                            .foregroundStyle(item.isDone ? palette.text3 : palette.text1)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: item.isDone)
            }
            if task.checklist.count > 3 {
                Text("+\(task.checklist.count - 3) more").font(.caption).foregroundStyle(palette.text3)
            }
        }
    }
}
