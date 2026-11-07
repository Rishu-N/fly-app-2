import PlannerCore
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct NowEntry: TimelineEntry {
    let date: Date
    let snapshot: NowSnapshot
    let theme: DialTheme
    var relevance: TimelineEntryRelevance?
}

/// Entries only at task boundaries (start, end, timer zero) + day-phase changes; the countdowns
/// inside each entry are system-rendered, so a day needs ~40 entries, not 1,440.
struct NowProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowEntry {
        NowEntry(date: Date(), snapshot: Self.sampleSnapshot(), theme: .aurora)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(from: Date()).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowEntry>) -> Void) {
        let now = Date()
        let list = entries(from: now)
        let refresh = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now.addingTimeInterval(21_600)
        completion(Timeline(entries: list, policy: .after(min(refresh, list.last?.date.addingTimeInterval(60) ?? refresh))))
    }

    private func entries(from now: Date) -> [NowEntry] {
        guard let data = WidgetSnapshot.load() else {
            return [NowEntry(date: now, snapshot: ScheduleEngine.snapshot(tasks: [], now: now), theme: DialTheme.stored)]
        }
        let theme = DialTheme(rawValue: data.theme) ?? .aurora
        let tasks = data.tasks
        var dates: Set<Date> = [now]
        let horizon = now.addingTimeInterval(24 * 3600)
        for task in tasks {
            for d in [task.start, task.end, task.start.addingTimeInterval(-TimeInterval((task.leadTimeMinutes ?? data.defaultLeadMinutes) * 60))]
            where d > now && d < horizon { dates.insert(d) }
            if task.status == .running, let s = task.session {
                let end = s.projectedEnd(at: now)
                if end > now, end < horizon { dates.insert(end) }
            }
        }
        let cal = Calendar.current
        for hour in [5, 9, 16, 20] {
            if let d = cal.nextDate(after: now, matching: DateComponents(hour: hour, minute: hour == 16 || hour == 20 ? 30 : 0), matchingPolicy: .nextTime), d < horizon {
                dates.insert(d)
            }
        }
        return dates.sorted().prefix(60).map { date in
            let snap = ScheduleEngine.snapshot(tasks: tasks, now: date)
            let active = snap.focusTask.map { $0.status.isActive || $0.start <= date.addingTimeInterval(300) } ?? false
            return NowEntry(date: date, snapshot: snap, theme: theme, relevance: TimelineEntryRelevance(score: active ? 1 : 0.2))
        }
    }

    static func sampleSnapshot() -> NowSnapshot {
        let now = Date()
        let t = PlanTask(title: "Deep work", start: now.addingTimeInterval(-600), durationMinutes: 50, category: .focus)
        let next = PlanTask(title: "Design review", start: now.addingTimeInterval(2400), durationMinutes: 30, category: .meeting)
        return ScheduleEngine.snapshot(tasks: [t, next], now: now)
    }
}

// MARK: - Widget

struct NowWidget: Widget {
    let kind = "DayflightNow" // keep in sync with WidgetSnapshotWriter.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowProvider()) { entry in
            NowWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground(theme: entry.theme, date: entry.date) }
                .widgetURL(DeepLink.now)
        }
        .configurationDisplayName("Now")
        .description("Your current block, its timer and what's next.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct WidgetBackground: View {
    let theme: DialTheme
    let date: Date
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            ZStack {
                theme.palette.surface
                LinearGradient(colors: DayPhase.at(date).stops(dark: scheme == .dark).map { $0.opacity(0.8) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else {
            Color.clear
        }
    }
}

struct NowWidgetView: View {
    let entry: NowEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let palette = entry.theme.palette
        switch family {
        case .systemSmall:
            SmallNow(entry: entry).environment(\.palette, palette)
        case .systemMedium:
            HStack(spacing: 14) {
                SmallNow(entry: entry)
                Divider()
                MediumList(entry: entry)
            }
            .environment(\.palette, palette)
        case .accessoryCircular:
            CircularNow(entry: entry)
        case .accessoryRectangular:
            RectangularNow(entry: entry)
        case .accessoryInline:
            InlineNow(entry: entry)
        default:
            SmallNow(entry: entry).environment(\.palette, palette)
        }
    }
}

// MARK: - Families

private struct SmallNow: View {
    let entry: NowEntry
    @Environment(\.palette) private var palette

    var body: some View {
        let snap = entry.snapshot
        VStack(alignment: .leading, spacing: 4) {
            switch snap.focus {
            case .active(let task):
                header("Now", task: task)
                Text(task.title).font(.system(size: 15, weight: .semibold)).lineLimit(2).foregroundStyle(palette.text1)
                Spacer(minLength: 0)
                if let s = task.session {
                    if task.status == .paused {
                        Text(formatClock(s.remaining(at: entry.date))).font(TypeRamp.timer(28)).foregroundStyle(palette.text2)
                        Text("Paused").font(.caption2).foregroundStyle(palette.text2)
                    } else {
                        Text(timerInterval: s.displayInterval(at: entry.date), countsDown: true)
                            .font(TypeRamp.timer(28))
                            .foregroundStyle(palette.text1)
                        ProgressView(timerInterval: s.displayInterval(at: entry.date), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(task.category.color)
                    }
                }
            case .due(let task):
                header("Now", task: task)
                Text(task.title).font(.system(size: 15, weight: .semibold)).lineLimit(2).foregroundStyle(palette.text1)
                Spacer(minLength: 0)
                Text(formatDuration(task.durationMinutes)).font(TypeRamp.timer(28)).foregroundStyle(palette.text1)
                Text("Tap to start").font(.caption2).foregroundStyle(palette.now)
            case .gap(let next):
                header("Next · \(next.start.formatted(date: .omitted, time: .shortened))", task: next)
                Text(next.title).font(.system(size: 15, weight: .semibold)).lineLimit(2).foregroundStyle(palette.text1)
                Spacer(minLength: 0)
                Text(timerInterval: entry.date...max(entry.date, next.start), countsDown: true)
                    .font(TypeRamp.timer(28))
                    .foregroundStyle(palette.text1)
                Text("until start").font(.caption2).foregroundStyle(palette.text2)
            case .clear:
                Eyebrow("Dayflight", color: palette.now)
                Spacer(minLength: 0)
                Text("Your day is clear").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.text1)
                Text("Tap to plan").font(.caption2).foregroundStyle(palette.text2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ text: String, task: PlanTask) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(task.category.color).frame(width: 4, height: 12)
            Eyebrow(text)
        }
    }
}

private struct MediumList: View {
    let entry: NowEntry
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let previous = entry.snapshot.previous {
                row(previous, glyph: previous.status == .completed ? "checkmark" : "minus", dim: true)
            }
            ForEach(entry.snapshot.upcoming) { task in
                row(task, glyph: nil, dim: false)
            }
            if entry.snapshot.previous == nil && entry.snapshot.upcoming.isEmpty {
                Text("Nothing else today").font(.caption).foregroundStyle(palette.text2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ task: PlanTask, glyph: String?, dim: Bool) -> some View {
        HStack(spacing: 6) {
            if let glyph {
                Image(systemName: glyph).font(.caption2.weight(.bold)).foregroundStyle(palette.text3).frame(width: 12)
            } else {
                Circle().fill(task.category.color).frame(width: 6, height: 6).frame(width: 12)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(task.title).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(palette.text1)
                Text(task.start.formatted(date: .omitted, time: .shortened)).font(.caption2.monospacedDigit()).foregroundStyle(palette.text2)
            }
        }
        .opacity(dim ? 0.6 : 1)
    }
}

private struct CircularNow: View {
    let entry: NowEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if case .active(let task) = entry.snapshot.focus, let s = task.session, task.status == .running {
                ProgressView(timerInterval: s.displayInterval(at: entry.date), countsDown: true) {
                    Image(systemName: task.category.symbol)
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .widgetAccentable()
            } else if let next = entry.snapshot.focusTask ?? entry.snapshot.upcoming.first {
                VStack(spacing: 0) {
                    Image(systemName: next.category.symbol).font(.caption)
                    Text(next.start.formatted(.dateTime.hour().minute())).font(.system(size: 11, weight: .semibold)).minimumScaleFactor(0.6)
                }
            } else {
                Image(systemName: "checkmark")
            }
        }
    }
}

private struct RectangularNow: View {
    let entry: NowEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch entry.snapshot.focus {
            case .active(let task):
                HStack(spacing: 4) {
                    Image(systemName: task.status == .paused ? "pause.fill" : "circle.fill").font(.system(size: 7))
                    if let s = task.session, task.status == .running {
                        Text(timerInterval: s.displayInterval(at: entry.date), countsDown: true).font(.headline.monospacedDigit())
                    } else if let s = task.session {
                        Text(formatClock(s.remaining(at: entry.date))).font(.headline.monospacedDigit())
                    }
                }
                .widgetAccentable()
                Text(task.title).font(.caption).lineLimit(1)
            case .due(let task), .gap(let task):
                Text(task.start.formatted(date: .omitted, time: .shortened)).font(.headline).widgetAccentable()
                Text(task.title).font(.caption).lineLimit(1)
            case .clear:
                Text("Day clear").font(.headline)
            }
            if let next = entry.snapshot.upcoming.first {
                Text("Next \(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)").font(.caption2).lineLimit(1).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineNow: View {
    let entry: NowEntry

    var body: some View {
        switch entry.snapshot.focus {
        case .active(let task):
            if let s = task.session {
                Text("\(task.title) · until \(s.projectedEnd(at: entry.date).formatted(date: .omitted, time: .shortened))")
            } else {
                Text(task.title)
            }
        case .due(let task), .gap(let task):
            Text("Next \(task.start.formatted(date: .omitted, time: .shortened)) · \(task.title)")
        case .clear:
            Text("Day clear")
        }
    }
}
