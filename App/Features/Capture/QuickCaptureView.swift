import PlannerCore
import SwiftUI

/// One-line capture: "gym 6:30pm 45m #health". Parsed locally on every keystroke (microseconds),
/// shown as chips, and Return adds the block while keeping the field open for rapid entry.
struct QuickCaptureView: View {
    let seed: String

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var added: [PlanTask] = []
    @FocusState private var focused: Bool

    private let examples = ["deep work 90m", "gym 6:30pm 45m", "standup 9:30-9:45", "call mum tomorrow 7pm", "read 30m #learning"]

    var body: some View {
        let now = Date()
        let parsed = QuickAddParser(calendar: model.store.calendar).parse(text, now: now)
        let duration = parsed.durationMinutes ?? model.settings.settings.defaultDurationMinutes
        let landing = parsed.start ?? model.nextFreeStart(duration: duration, on: DayKey(now, calendar: model.store.calendar), now: now)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("Quick add")
                Spacer()
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(palette.now)
                TextField("What, when, how long…", text: $text)
                    .font(.title3)
                    .focused($focused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .onSubmit(submit)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(palette.surface, in: Capsule())

            if text.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(examples, id: \.self) { example in
                            Button(example) { text = example }
                                .font(.footnote.monospaced())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(palette.surface2, in: Capsule())
                                .foregroundStyle(palette.text2)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                // Live tokens
                HStack(spacing: 8) {
                    chip(parsed.title.isEmpty ? "Title?" : parsed.title, symbol: "textformat", tint: palette.text1)
                    chip(landing.clockString(), symbol: "clock", tint: parsed.start == nil ? palette.text2 : palette.now)
                    chip(formatDuration(duration), symbol: "timer", tint: parsed.durationMinutes == nil ? palette.text2 : palette.now)
                    let category = parsed.category ?? TaskCategory.guess(fromTitle: parsed.title)
                    chip(category.displayName, symbol: category.symbol, tint: category.color)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Text(landingDescription(start: landing, duration: duration, explicit: parsed.start != nil))
                    .font(.footnote)
                    .foregroundStyle(palette.text2)
            }

            if !added.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(added.suffix(3)) { task in
                        Label("\(task.title) · \(task.windowString())", systemImage: "checkmark")
                            .font(.footnote)
                            .foregroundStyle(palette.success)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear {
            text = seed.isEmpty ? "" : seed + " "
            focused = true
        }
        .animation(Motion.snappy, value: text.isEmpty)
        .animation(Motion.snappy, value: added.count)
    }

    private func chip(_ label: String, symbol: String, tint: Color) -> some View {
        Label(label, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(palette.surface, in: Capsule())
    }

    private func landingDescription(start: Date, duration: Int, explicit: Bool) -> String {
        let end = start.addingTimeInterval(TimeInterval(duration * 60))
        let day = Calendar.current.isDateInToday(start) ? "Today" : start.formatted(.dateTime.weekday(.wide))
        let overlap = model.store.tasks(in: DateInterval(start: start, end: end)).first { !$0.status.isClosed }
        var s = "\(day) \(start.clockString())–\(end.clockString())"
        if !explicit { s += " · first free slot" }
        if let overlap { s += " · overlaps \(overlap.title)" }
        return s
    }

    private func submit() {
        guard let task = model.quickAdd(text) else { return }
        added.append(task)
        text = ""
        focused = true
    }
}
