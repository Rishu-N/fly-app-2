import PlannerCore
import SwiftUI

/// Week zoom level (UX-1 §7): seven columns of the day window, the selected day magnified
/// ("the lens, sideways"), others as density strips. Tap a column to focus it, tap again to
/// open its day timeline.
struct WeekOverviewView: View {
    @Binding var selected: DayKey
    var onOpenDay: (DayKey) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let cal = model.store.calendar
        let selectedDate = selected.startDate(calendar: cal)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        let days = (0..<7).map { DayKey(cal.date(byAdding: .day, value: $0, to: weekStart) ?? weekStart, calendar: cal) }
        let s = model.settings.settings
        let startHour = s.dayStartHour
        let endHour = max(startHour + 1, min(24, s.dayEndHour + 1))
        let now = max(model.clockTick, Date())

        GeometryReader { geo in
            let spacing: CGFloat = 4
            let available = geo.size.width - spacing * 6
            let focusWidth = min(available * 0.34, 140)
            let otherWidth = (available - focusWidth) / 6
            HStack(alignment: .top, spacing: spacing) {
                ForEach(days, id: \.self) { day in
                    let isFocus = day == selected
                    DayColumn(
                        day: day,
                        tasks: model.store.tasks(on: day),
                        busy: model.calendarOverlay.events(on: day, calendar: cal).filter { !$0.isAllDay },
                        startHour: startHour,
                        endHour: endHour,
                        isFocus: isFocus,
                        isToday: day == DayKey(now, calendar: cal),
                        now: now
                    )
                    .frame(width: isFocus ? focusWidth : otherWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isFocus {
                            onOpenDay(day)
                        } else {
                            withAnimation(Motion.glide) { selected = day }
                        }
                    }
                }
            }
            .animation(Motion.glide, value: selected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

private struct DayColumn: View {
    let day: DayKey
    let tasks: [PlanTask]
    let busy: [BusyBlock]
    let startHour: Int
    let endHour: Int
    let isFocus: Bool
    let isToday: Bool
    let now: Date

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let cal = model.store.calendar
        let date = day.startDate(calendar: cal)
        let windowStart = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: date) ?? date
        let totalMinutes = CGFloat((endHour - startHour) * 60)
        let plannedMinutes = tasks.filter { !$0.status.isClosed || $0.status == .completed }.reduce(0) { $0 + $1.durationMinutes }

        VStack(spacing: 6) {
            VStack(spacing: 1) {
                Text(date.formatted(.dateTime.weekday(isFocus ? .abbreviated : .narrow)))
                    .font(TypeRamp.eyebrow)
                    .foregroundStyle(isToday ? palette.now : palette.text3)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(isFocus ? .title3 : .callout, weight: isFocus ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(isToday ? palette.now : palette.text1)
            }
            GeometryReader { geo in
                let h = geo.size.height
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: isFocus ? 14 : 8, style: .continuous)
                        .fill(isFocus ? palette.surface : palette.surface.opacity(0.5))
                    ForEach(busy) { event in
                        let y = CGFloat(event.start.timeIntervalSince(windowStart) / 60) / totalMinutes * h
                        let height = max(2, CGFloat(event.durationMinutes) / totalMinutes * h)
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color(hex: event.colorHex).opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .frame(height: height)
                            .offset(y: y)
                            .padding(.horizontal, 3)
                    }
                    ForEach(tasks) { task in
                        let y = CGFloat(task.start.timeIntervalSince(windowStart) / 60) / totalMinutes * h
                        let height = max(3, CGFloat(task.durationMinutes) / totalMinutes * h - 1)
                        if y + height > 0, y < h {
                            RoundedRectangle(cornerRadius: isFocus ? 5 : 3, style: .continuous)
                                .fill(task.category.color.opacity(task.status.isClosed && task.status != .completed ? 0.25 : (scheme == .dark ? 0.85 : 0.75)))
                                .overlay(alignment: .topLeading) {
                                    if isFocus, height > 18 {
                                        Text(task.title)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                            .padding(.horizontal, 4)
                                            .padding(.top, 2)
                                    }
                                }
                                .frame(height: height)
                                .offset(y: max(0, y))
                                .padding(.horizontal, isFocus ? 4 : 2)
                        }
                    }
                    if isToday {
                        let y = CGFloat(now.timeIntervalSince(windowStart) / 60) / totalMinutes * h
                        if y >= 0, y <= h {
                            Rectangle().fill(palette.now).frame(height: 1.5).offset(y: y)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: isFocus ? 14 : 8, style: .continuous))
            }
            Text(plannedMinutes > 0 ? formatDuration(plannedMinutes) : "–")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).day())), \(tasks.count) blocks, \(formatDuration(plannedMinutes)) planned")
        .accessibilityAddTraits(isFocus ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(isFocus ? "Double-tap to open the day" : "Double-tap to focus this day")
    }
}
