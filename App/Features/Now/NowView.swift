import PlannerCore
import SwiftUI

/// Home — "The Now Lens": Last (compressed) · Now (magnified, live) · Next · Next.
/// "Now" never moves; time flows through it.
struct NowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Namespace private var conveyor
    @State private var pullArmed = true

    var body: some View {
        // Reading `clockTick` re-evaluates exactly at schedule boundaries (see AppModel).
        let now = max(model.clockTick, Date())
        let snapshot = model.store.snapshot(at: now)
        let today = model.store.tasks(on: DayKey(now, calendar: model.store.calendar))

        ScrollView {
            VStack(spacing: 12) {
                NowHeader(now: now, today: today, snapshot: snapshot)

                if let previous = snapshot.previous {
                    LastLane(task: previous, now: now)
                        .matchedGeometryEffect(id: previous.id, in: conveyor)
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity)))
                }

                LensCard(snapshot: snapshot, now: now, leadMinutes: model.settings.settings.defaultLeadMinutes, namespace: conveyor)

                ForEach(Array(snapshot.upcoming.enumerated()), id: \.element.id) { index, task in
                    NextRow(task: task, now: now, prominent: index == 0, lateMinutes: index == 0 ? snapshot.projectedLateMinutes : 0)
                        .matchedGeometryEffect(id: task.id, in: conveyor)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                TailRow(today: today, snapshot: snapshot, now: now)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
            .animation(Motion.conveyor, value: snapshot.focusTask?.id)
            .animation(Motion.conveyor, value: snapshot.previous?.id)
            .animation(Motion.conveyor, value: snapshot.upcoming.map(\.id))
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always)
        // Pull down to capture.
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, offset in
            if offset < -80, pullArmed {
                pullArmed = false
                model.captureSeed = ""
                model.showCapture = true
            } else if offset > -10, !pullArmed {
                pullArmed = true
            }
        }
        .background(palette.bg.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            Button {
                model.captureSeed = ""
                model.showCapture = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.text1)
                    .frame(width: 58, height: 58)
                    .floatingGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 16)
            .accessibilityLabel("Add a block")
            .sensoryFeedback(.impact(weight: .light), trigger: model.showCapture)
        }
    }
}

// MARK: - Header

private struct NowHeader: View {
    let now: Date
    let today: [PlanTask]
    let snapshot: NowSnapshot
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(now.formatted(.dateTime.weekday(.wide)))
                    Text(now.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(.largeTitle, weight: .bold))
                        .foregroundStyle(palette.text1)
                }
                Spacer()
                DriftChip(snapshot: snapshot)
                Button { model.showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(palette.text2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            DayProgressLine(today: today, focusID: snapshot.focusTask?.id, now: now)
        }
        .padding(.top, 8)
    }
}

/// Segment per block: filled = done, tinted = current, outlined = future.
private struct DayProgressLine: View {
    let today: [PlanTask]
    let focusID: UUID?
    let now: Date
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 3) {
            if today.isEmpty {
                Capsule().fill(palette.separator).frame(height: 3)
            }
            ForEach(today) { task in
                let phase = task.phase(at: now)
                Capsule()
                    .fill(fill(for: task, phase: phase))
                    .overlay(Capsule().stroke(palette.separator, lineWidth: phase == .upcoming ? 1 : 0))
                    .frame(height: task.id == focusID ? 5 : 3)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 5)
        .animation(Motion.snappy, value: focusID)
        .accessibilityElement()
        .accessibilityLabel("\(today.filter { $0.status == .completed }.count) of \(today.count) blocks done today")
    }

    private func fill(for task: PlanTask, phase: TaskPhase) -> Color {
        if task.id == focusID { return palette.now }
        switch phase {
        case .completed: return task.category.color
        case .cancelled, .skipped, .missed: return palette.text3.opacity(0.35)
        default: return .clear
        }
    }
}

/// "+6m" when the running block will push into the next one. Tap → push / shift / ignore.
private struct DriftChip: View {
    let snapshot: NowSnapshot
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        if snapshot.projectedLateMinutes > 0, let next = snapshot.upcoming.first {
            let late = snapshot.projectedLateMinutes
            Menu {
                Button("Push “\(next.title)” \(late) min", systemImage: "arrow.down") {
                    var moved = next
                    moved.start = next.start.addingTimeInterval(TimeInterval(late * 60))
                    model.applyWithUndo(ChangeSet(label: "Pushed \(next.title)", upserts: [moved]),
                                        toast: "Pushed \(next.title) by \(late) min", symbol: "arrow.down")
                }
                Button("Shift rest of day \(late) min", systemImage: "arrow.down.to.line") {
                    model.shiftRest(after: next, minutes: late)
                }
                Button("Ignore", systemImage: "xmark", role: .cancel) {}
            } label: {
                Label("+\(late)m", systemImage: "clock.badge.exclamationmark")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(palette.warning)
                    .background(palette.warning.opacity(0.14), in: Capsule())
            }
            .accessibilityLabel("Running \(late) minutes late. Adjust schedule")
        } else {
            Label("On time", systemImage: "checkmark")
                .font(.footnote.weight(.medium))
                .labelStyle(.titleOnly)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(palette.text2)
                .background(palette.surface2, in: Capsule())
        }
    }
}

// MARK: - Last lane

private struct LastLane: View {
    let task: PlanTask
    let now: Date
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let phase = task.phase(at: now)
        HStack(spacing: 12) {
            Image(systemName: glyph(phase))
                .font(.body.weight(.semibold))
                .foregroundStyle(phase == .completed ? palette.success : palette.text3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(phase == .cancelled, color: palette.text3)
                    .foregroundStyle(palette.text1)
                    .lineLimit(1)
                Text(detail(phase))
                    .font(.caption)
                    .foregroundStyle(palette.text2)
            }
            Spacer(minLength: 8)
            if phase == .missed {
                Button("Reschedule") {
                    var moved = task
                    moved.start = model.nextFreeStart(duration: task.durationMinutes, on: DayKey(now, calendar: model.store.calendar), now: now)
                    model.applyWithUndo(ChangeSet(label: "Rescheduled \(task.title)", upserts: [moved]),
                                        toast: "Moved to \(moved.start.clockString())", symbol: "arrow.uturn.forward")
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if phase.isDone, now.timeIntervalSince(task.updatedAt) < 600 {
                Button {
                    model.perform(.reopen, on: task, undoable: false)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .foregroundStyle(palette.text2)
                .accessibilityLabel("Reopen \(task.title)")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.separator, lineWidth: 0.5))
        .opacity(0.75)
        .accessibilityElement(children: .combine)
    }

    private func glyph(_ phase: TaskPhase) -> String {
        switch phase {
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .skipped: "forward.end.circle"
        case .missed: "moon.zzz"
        default: "circle"
        }
    }

    private func detail(_ phase: TaskPhase) -> String {
        switch phase {
        case .completed:
            if let s = task.session {
                return "\(formatDuration(Int(s.elapsed(at: now) / 60))) of \(formatDuration(task.durationMinutes))"
            }
            return "Done"
        case .cancelled: return "Cancelled · \(task.windowString())"
        case .skipped: return "Skipped · \(task.windowString())"
        case .missed: return "Didn't start · \(task.windowString())"
        default: return task.windowString()
        }
    }
}

// MARK: - Next rows

private struct NextRow: View {
    let task: PlanTask
    let now: Date
    let prominent: Bool
    let lateMinutes: Int
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(task.start.clockString())
                    .font(TypeRamp.timeLabel)
                    .foregroundStyle(palette.text1)
                    .frame(minWidth: 64, alignment: .leading)
                Capsule().fill(task.category.color).frame(width: 3, height: prominent ? 32 : 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(prominent ? TypeRamp.rowTitle : .subheadline.weight(.semibold))
                        .foregroundStyle(palette.text1)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(formatDuration(task.durationMinutes))
                        Text("·")
                        Text(relative)
                        if lateMinutes > 0 {
                            Text("· you'll be \(lateMinutes)m late").foregroundStyle(palette.warning)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(palette.text2)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.text3)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            if expanded {
                if !task.notes.isEmpty {
                    Text(task.notes).font(.footnote).foregroundStyle(palette.text2).lineLimit(3)
                }
                HStack(spacing: 10) {
                    Button("Start now", systemImage: "play.fill") { model.start(task) }
                        .buttonStyle(PillButtonStyle(fill: palette.now, foreground: palette.onNow, height: 44))
                    Button("Skip", systemImage: "forward.end") { model.perform(.skip, on: task) }
                        .buttonStyle(PillButtonStyle(fill: palette.surface2, foreground: palette.text1, height: 44))
                    Button {
                        model.editingTask = task
                    } label: { Image(systemName: "pencil") }
                        .buttonStyle(CircleButtonStyle(fill: palette.surface2, foreground: palette.text1, size: 44))
                        .accessibilityLabel("Edit")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, prominent ? 14 : 10)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(prominent ? 1 : 0.85)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Motion.glide) { expanded.toggle() } }
        .contextMenu {
            Button("Start now", systemImage: "play.fill") { model.start(task) }
            Button("Edit", systemImage: "pencil") { model.editingTask = task }
            Button("Skip", systemImage: "forward.end") { model.perform(.skip, on: task) }
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(task) }
        }
        .sensoryFeedback(.selection, trigger: expanded)
        .accessibilityElement(children: expanded ? .contain : .combine)
        .accessibilityHint(expanded ? "" : "Double-tap for options")
    }

    private var relative: String {
        let minutes = Int((task.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes)m" }
        return "in \(formatDuration(minutes))"
    }
}

private struct TailRow: View {
    let today: [PlanTask]
    let snapshot: NowSnapshot
    let now: Date
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let shown = Set(snapshot.upcoming.map(\.id) + [snapshot.focusTask?.id].compactMap { $0 })
        let later = today.filter { $0.status == .planned && $0.start > now && !shown.contains($0.id) }
        if !later.isEmpty, let last = later.last {
            Button {
                model.selectedTab = .plan
            } label: {
                HStack {
                    Text("+\(later.count) later · last ends \(last.end.clockString())")
                    Image(systemName: "chevron.right")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.text2)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(.plain)
        }
    }
}
