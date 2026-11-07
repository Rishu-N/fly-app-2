import PlannerCore
import SwiftUI

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(selected: $model.selectedPlanDay)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                Divider().overlay(palette.separator)
                DayTimelineView(day: model.selectedPlanDay)
            }
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        withAnimation(Motion.snappy) { model.selectedPlanDay = DayKey(Date(), calendar: model.store.calendar) }
                    }
                    .disabled(model.selectedPlanDay == DayKey(Date(), calendar: model.store.calendar))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let cal = model.store.calendar
                        let start = model.nextFreeStart(duration: model.settings.settings.defaultDurationMinutes, on: model.selectedPlanDay, now: max(Date(), model.selectedPlanDay.startDate(calendar: cal)))
                        model.editingTask = PlanTask(title: "", start: start, durationMinutes: model.settings.settings.defaultDurationMinutes)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New block")
                }
            }
            .task(id: model.selectedPlanDay) {
                await model.store.ensureLoaded(model.selectedPlanDay.adding(days: -7, calendar: model.store.calendar).interval(calendar: model.store.calendar).union(model.selectedPlanDay.adding(days: 7, calendar: model.store.calendar).interval(calendar: model.store.calendar)))
            }
        }
    }

    private var title: String {
        let date = model.selectedPlanDay.startDate(calendar: model.store.calendar)
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

private extension DateInterval {
    func union(_ other: DateInterval) -> DateInterval {
        DateInterval(start: min(start, other.start), end: max(end, other.end))
    }
}

/// Seven days with a density dot. Swipe horizontally to change week.
struct WeekStrip: View {
    @Binding var selected: DayKey
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let cal = model.store.calendar
        let selectedDate = selected.startDate(calendar: cal)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        let days = (0..<7).map { DayKey(cal.date(byAdding: .day, value: $0, to: weekStart) ?? weekStart, calendar: cal) }
        let today = DayKey(Date(), calendar: cal)

        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let date = day.startDate(calendar: cal)
                let count = model.store.tasks(on: day).count
                let isSelected = day == selected
                Button {
                    withAnimation(Motion.snappy) { selected = day }
                } label: {
                    VStack(spacing: 4) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(TypeRamp.eyebrow)
                            .foregroundStyle(palette.text3)
                        Text(date.formatted(.dateTime.day()))
                            .font(.system(.callout, weight: isSelected ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(isSelected ? palette.onNow : (day == today ? palette.now : palette.text1))
                            .frame(width: 34, height: 34)
                            .background {
                                if isSelected { Circle().fill(palette.now) }
                            }
                        HStack(spacing: 2) {
                            ForEach(0..<min(3, count), id: \.self) { _ in
                                Circle().fill(palette.text3).frame(width: 3, height: 3)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).day())), \(count) blocks")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.top, 4)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let delta = value.translation.width < 0 ? 7 : -7
                withAnimation(Motion.glide) { selected = selected.adding(days: delta, calendar: cal) }
            }
        )
        .sensoryFeedback(.selection, trigger: selected)
    }
}
