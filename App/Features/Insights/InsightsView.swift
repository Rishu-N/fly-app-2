import Charts
import PlannerCore
import SwiftUI

/// Plan vs reality: focused time per day by category, on-time starts, drift and streak.
/// Computed on demand from the store (one pass over 7 or 30 days).
struct InsightsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var range = 7

    var body: some View {
        let now = Date()
        let cal = model.store.calendar
        let insights = InsightsEngine.range(endingOn: DayKey(now, calendar: cal), days: range, calendar: cal, now: now) {
            model.store.tasks(on: $0)
        }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Range", selection: $range) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(title: "Focused", value: formatDuration(insights.focusedMinutes),
                                 detail: "of \(formatDuration(insights.plannedMinutes)) planned", symbol: "timer")
                        StatTile(title: "Done", value: percent(insights.completionRate),
                                 detail: "\(insights.completed) of \(insights.total) blocks", symbol: "checkmark.circle")
                        StatTile(title: "On-time starts", value: percent(insights.onTimeRate),
                                 detail: "within 5 min of plan", symbol: "flag.checkered")
                        StatTile(title: "Streak", value: "\(insights.streak) day\(insights.streak == 1 ? "" : "s")",
                                 detail: driftText(insights.averageStartDriftMinutes), symbol: "flame")
                    }

                    ChartCard(title: "Focused time by day") {
                        Chart {
                            ForEach(insights.days) { day in
                                ForEach(TaskCategory.allCases) { category in
                                    let minutes = day.focusedMinutesByCategory[category] ?? 0
                                    if minutes > 0 {
                                        BarMark(
                                            x: .value("Day", day.day.startDate(calendar: cal), unit: .day),
                                            y: .value("Minutes", minutes)
                                        )
                                        .foregroundStyle(by: .value("Category", category.displayName))
                                    }
                                }
                            }
                        }
                        .chartForegroundStyleScale(domain: TaskCategory.allCases.map(\.displayName),
                                                   range: TaskCategory.allCases.map(\.color))
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: range > 7 ? 7 : 1)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.narrow))
                            }
                        }
                        .frame(height: 200)
                    }

                    ChartCard(title: "Planned vs done") {
                        Chart(insights.days) { day in
                            LineMark(x: .value("Day", day.day.startDate(calendar: cal), unit: .day),
                                     y: .value("Planned", day.plannedMinutes))
                                .foregroundStyle(by: .value("Series", "Planned"))
                            LineMark(x: .value("Day", day.day.startDate(calendar: cal), unit: .day),
                                     y: .value("Focused", day.focusedMinutes))
                                .foregroundStyle(by: .value("Series", "Focused"))
                        }
                        .chartForegroundStyleScale(domain: ["Planned", "Focused"], range: [palette.text3, palette.now])
                        .frame(height: 160)
                    }

                    if let top = insights.topCategory {
                        Label("Most of your focus went to \(top.displayName.lowercased()).", systemImage: top.symbol)
                            .font(.subheadline)
                            .foregroundStyle(palette.text2)
                    }

                    Button {
                        dismiss()
                        model.selectedTab = .assistant
                    } label: {
                        Label("Review with the assistant", systemImage: "sparkles")
                    }
                    .buttonStyle(PillButtonStyle(fill: palette.surface2, foreground: palette.text1, height: 48))
                }
                .padding(16)
            }
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: range) {
                let start = DayKey(Date(), calendar: cal).adding(days: -range, calendar: cal).startDate(calendar: cal)
                await model.store.ensureLoaded(DateInterval(start: start, end: Date()))
            }
        }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func driftText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m == 0 { return "starting right on time" }
        return m > 0 ? "starting \(m) min late on average" : "starting \(-m) min early on average"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title.uppercased(), systemImage: symbol)
                .font(TypeRamp.eyebrow)
                .tracking(1)
                .foregroundStyle(palette.text2)
            Text(value)
                .font(TypeRamp.timer(34))
                .foregroundStyle(palette.text1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.caption)
                .foregroundStyle(palette.text2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(title)
            content
        }
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
