import PlannerCore
import SwiftUI

/// Vertical hour grid with absolutely-positioned blocks, a live now-line, dashed free gaps and
/// long-press-drag rescheduling with a 5-minute snap.
struct DayTimelineView: View {
    let day: DayKey

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var dragging: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var scrolledToNow = false

    private let hourHeight: CGFloat = 72
    private let gutter: CGFloat = 56
    private var pointsPerMinute: CGFloat { hourHeight / 60 }

    var body: some View {
        let cal = model.store.calendar
        let dayStart = day.startDate(calendar: cal)
        let tasks = model.store.tasks(on: day)
        let lanes = Self.assignLanes(tasks)
        let now = max(model.clockTick, Date())
        let isToday = cal.isDate(now, inSameDayAs: dayStart)

        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geo in
                    let width = geo.size.width - gutter - 16
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        freeGaps(tasks: tasks, dayStart: dayStart, width: width, now: now)
                        ForEach(tasks) { task in
                            let lane = lanes[task.id] ?? (0, 1)
                            let laneWidth = width / CGFloat(lane.count)
                            TimelineBlock(task: task, now: now, compact: task.durationMinutes < 25)
                                .frame(width: laneWidth - 4, height: max(26, CGFloat(task.durationMinutes) * pointsPerMinute - 3))
                                .offset(x: gutter + CGFloat(lane.index) * laneWidth, y: y(for: task.start, dayStart: dayStart) + (dragging == task.id ? dragOffset : 0))
                                .zIndex(dragging == task.id ? 10 : 1)
                                .scaleEffect(dragging == task.id ? 1.02 : 1, anchor: .center)
                                .shadow(color: .black.opacity(dragging == task.id ? 0.18 : 0), radius: 12, y: 6)
                                .onTapGesture { model.editingTask = task }
                                .gesture(rescheduleGesture(for: task))
                                .accessibilityAction(named: "Move 15 minutes later") { move(task, minutes: 15) }
                                .accessibilityAction(named: "Move 15 minutes earlier") { move(task, minutes: -15) }
                        }
                        if isToday {
                            nowLine(y: y(for: now, dayStart: dayStart), width: geo.size.width)
                        }
                    }
                }
                .frame(height: hourHeight * 24 + 24)
                .overlay(alignment: .topLeading) {
                    // Invisible anchors for scrolling.
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { h in
                            Color.clear.frame(height: hourHeight).id(h)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .scrollIndicators(.hidden)
            .onAppear { scroll(proxy, isToday: isToday, now: now, tasks: tasks, animated: false) }
            .onChange(of: day) { _, _ in scroll(proxy, isToday: isToday, now: now, tasks: tasks, animated: true) }
        }
        .sensoryFeedback(.selection, trigger: snappedMinutes)
    }

    // MARK: Pieces

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d:00", hour))
                        .font(TypeRamp.tick)
                        .foregroundStyle(palette.text3)
                        .frame(width: gutter - 12, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle().fill(palette.separator.opacity(0.7)).frame(height: 0.5)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
        .padding(.top, 12)
        .accessibilityHidden(true)
    }

    private func nowLine(y: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Circle().fill(palette.now).frame(width: 8, height: 8)
            Rectangle().fill(palette.now).frame(height: 1.5)
        }
        .frame(width: width - gutter + 8)
        .offset(x: gutter - 8, y: y - 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func freeGaps(tasks: [PlanTask], dayStart: Date, width: CGFloat, now: Date) -> some View {
        let s = model.settings.settings
        let cal = model.store.calendar
        let windowStart = cal.date(bySettingHour: s.dayStartHour, minute: 0, second: 0, of: dayStart) ?? dayStart
        let windowEnd = cal.date(bySettingHour: min(23, s.dayEndHour), minute: 0, second: 0, of: dayStart) ?? dayStart
        if windowEnd > windowStart, !tasks.isEmpty {
            let gaps = ScheduleMath.freeSlots(in: DateInterval(start: windowStart, end: windowEnd), tasks: tasks, minimumMinutes: 30, now: now)
            ForEach(gaps, id: \.start) { gap in
                let minutes = Int(gap.duration / 60)
                Button {
                    model.editingTask = PlanTask(title: "", start: ScheduleMath.roundUp(gap.start, toMinutes: 5), durationMinutes: min(minutes, model.settings.settings.defaultDurationMinutes))
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .overlay {
                            Text("Free \(formatDuration(minutes))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(palette.text3)
                        }
                }
                .buttonStyle(.plain)
                .frame(width: width - 4, height: max(24, CGFloat(minutes) * pointsPerMinute - 6))
                .offset(x: gutter, y: y(for: gap.start, dayStart: dayStart) + 3)
                .accessibilityLabel("Free \(formatDuration(minutes)) at \(gap.start.clockString()). Add a block")
            }
        }
    }

    // MARK: Geometry

    private func y(for date: Date, dayStart: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 60) * pointsPerMinute + 12
    }

    private var snappedMinutes: Int {
        Int((dragOffset / pointsPerMinute / 5).rounded()) * 5
    }

    private func rescheduleGesture(for task: PlanTask) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard !task.status.isClosed else { return }
                switch value {
                case .second(true, let drag?):
                    dragging = task.id
                    dragOffset = drag.translation.height
                case .second(true, nil):
                    dragging = task.id
                default:
                    break
                }
            }
            .onEnded { _ in
                defer {
                    withAnimation(Motion.glide) {
                        dragging = nil
                        dragOffset = 0
                    }
                }
                guard dragging == task.id, snappedMinutes != 0 else { return }
                move(task, minutes: snappedMinutes)
            }
    }

    private func move(_ task: PlanTask, minutes: Int) {
        var moved = task
        moved.start = task.start.addingTimeInterval(TimeInterval(minutes * 60))
        withAnimation(Motion.glide) {
            model.applyWithUndo(ChangeSet(label: "Moved \(task.title)", upserts: [moved]),
                                toast: "\(task.title) → \(moved.start.clockString())", symbol: "arrow.up.and.down")
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, isToday: Bool, now: Date, tasks: [PlanTask], animated: Bool) {
        let cal = model.store.calendar
        let hour: Int
        if isToday {
            hour = max(0, cal.component(.hour, from: now) - 1)
        } else if let first = tasks.first {
            hour = max(0, cal.component(.hour, from: first.start) - 1)
        } else {
            hour = max(0, model.settings.settings.dayStartHour)
        }
        if animated {
            withAnimation(Motion.glide) { proxy.scrollTo(hour, anchor: .top) }
        } else {
            proxy.scrollTo(hour, anchor: .top)
        }
    }

    /// Greedy lane assignment for overlapping blocks: (index, laneCount) per task.
    static func assignLanes(_ tasks: [PlanTask]) -> [UUID: (index: Int, count: Int)] {
        var result: [UUID: (index: Int, count: Int)] = [:]
        var cluster: [(task: PlanTask, lane: Int)] = []
        var clusterEnd = Date.distantPast
        var laneEnds: [Date] = []

        func flush() {
            let count = max(1, (cluster.map(\.lane).max() ?? 0) + 1)
            for entry in cluster { result[entry.task.id] = (entry.lane, count) }
            cluster.removeAll()
            laneEnds.removeAll()
        }

        for task in tasks.sorted(by: { $0.start < $1.start }) {
            if task.start >= clusterEnd { flush() }
            if let free = laneEnds.firstIndex(where: { $0 <= task.start }) {
                laneEnds[free] = task.end
                cluster.append((task, free))
            } else {
                laneEnds.append(task.end)
                cluster.append((task, laneEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, task.end)
        }
        flush()
        return result
    }
}

/// One block on the timeline: 14 % category tint + 3 pt bar, plan-vs-actual for finished ones.
private struct TimelineBlock: View {
    let task: PlanTask
    let now: Date
    let compact: Bool
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let phase = task.phase(at: now)
        let done = phase.isDone || phase == .missed
        HStack(alignment: .top, spacing: 8) {
            Capsule().fill(task.category.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(phase == .cancelled || phase == .skipped)
                        .foregroundStyle(palette.text1)
                        .lineLimit(compact ? 1 : 2)
                    if task.seriesID != nil {
                        Image(systemName: "repeat").font(.caption2).foregroundStyle(palette.text3)
                    }
                    if compact { Spacer(minLength: 0); statusGlyph(phase) }
                }
                if !compact {
                    HStack(spacing: 6) {
                        Text("\(task.windowString()) · \(formatDuration(task.durationMinutes))")
                        Spacer(minLength: 0)
                        statusGlyph(phase)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.text2)
                    if let actual = actualText(phase) {
                        Text(actual).font(.caption2).foregroundStyle(palette.text3)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, compact ? 3 : 7)
        .padding(.trailing, 8)
        .background(task.category.color.opacity(scheme == .dark ? 0.22 : 0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if task.status.isActive {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.now, lineWidth: 1.5)
            }
        }
        .opacity(done ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-tap to edit. Long-press and drag to move.")
    }

    @ViewBuilder
    private func statusGlyph(_ phase: TaskPhase) -> some View {
        switch phase {
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.success)
        case .running: Image(systemName: "play.circle.fill").foregroundStyle(palette.now)
        case .paused: Image(systemName: "pause.circle.fill").foregroundStyle(palette.text2)
        case .overrun: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(palette.warning)
        case .missed: Image(systemName: "moon.zzz").foregroundStyle(palette.text3)
        default: EmptyView()
        }
    }

    private func actualText(_ phase: TaskPhase) -> String? {
        guard phase == .completed, let s = task.session, let ended = s.endedAt else { return nil }
        return "Actual \(s.startedAt.clockString())–\(ended.clockString())"
    }
}
