import PlannerCore
import SwiftUI

/// Create / edit a block. Smart defaults mean a new block needs only a title.
struct TaskEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PlanTask
    @State private var reminder: ReminderChoice
    @State private var repeatChoice: RepeatChoice = .none
    @State private var weeklyDays: Set<Int> = []
    @State private var newItem = ""
    @FocusState private var titleFocused: Bool
    private let isNew: Bool

    enum ReminderChoice: Hashable { case defaultLead, custom(Int), off }
    enum RepeatChoice: String, CaseIterable, Identifiable { case none, daily, weekdays, weekly; var id: String { rawValue } }

    init(task: PlanTask) {
        _draft = State(initialValue: task)
        isNew = AppModel.shared.store.task(task.id) == nil
        if !task.remind {
            _reminder = State(initialValue: .off)
        } else if let lead = task.leadTimeMinutes {
            _reminder = State(initialValue: .custom(lead))
        } else {
            _reminder = State(initialValue: .defaultLead)
        }
        _weeklyDays = State(initialValue: [Calendar.current.component(.weekday, from: task.start)])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                        .font(.title3.weight(.semibold))
                        .focused($titleFocused)
                    categoryPicker
                }

                Section("When") {
                    DatePicker("Starts", selection: $draft.start, displayedComponents: [.date, .hourAndMinute])
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Stepper(formatDuration(draft.durationMinutes), value: $draft.durationMinutes, in: 5...720, step: 5)
                                .fixedSize()
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach([15, 25, 30, 45, 60, 90, 120], id: \.self) { m in
                                    Button(formatDuration(m)) {
                                        withAnimation(Motion.micro) { draft.durationMinutes = m }
                                    }
                                    .font(.footnote.weight(.semibold).monospacedDigit())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(draft.durationMinutes == m ? palette.now : palette.surface2, in: Capsule())
                                    .foregroundStyle(draft.durationMinutes == m ? palette.onNow : palette.text1)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        Text("Ends \(draft.end.clockString()) · the timer runs the full \(formatDuration(draft.durationMinutes)) from when you tap Start.")
                            .font(.caption)
                            .foregroundStyle(palette.text2)
                    }
                }

                Section("Reminder") {
                    Picker("Remind me", selection: $reminder) {
                        Text("Default (\(model.settings.settings.defaultLeadMinutes) min before)").tag(ReminderChoice.defaultLead)
                        ForEach(PlannerSettings.leadTimeChoices, id: \.self) { m in
                            Text(m == 0 ? "At start" : "\(m) min before").tag(ReminderChoice.custom(m))
                        }
                        Text("Off").tag(ReminderChoice.off)
                    }
                }

                if isNew || draft.seriesID == nil {
                    Section("Repeat") {
                        Picker("Repeat", selection: $repeatChoice) {
                            Text("Never").tag(RepeatChoice.none)
                            Text("Every day").tag(RepeatChoice.daily)
                            Text("Weekdays").tag(RepeatChoice.weekdays)
                            Text("Weekly").tag(RepeatChoice.weekly)
                        }
                        if repeatChoice == .weekly {
                            WeekdayPicker(selection: $weeklyDays)
                        }
                    }
                } else if let seriesID = draft.seriesID, let series = model.store.series[seriesID] {
                    Section("Repeat") {
                        LabeledContent("Routine", value: series.rule.label)
                        Button("End this routine", role: .destructive) {
                            model.store.endSeries(seriesID)
                            dismiss()
                        }
                    }
                }

                Section("Checklist") {
                    ForEach($draft.checklist) { $item in
                        HStack {
                            Button {
                                item.isDone.toggle()
                            } label: {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? palette.success : palette.text3)
                            }
                            .buttonStyle(.plain)
                            TextField("Step", text: $item.title)
                        }
                    }
                    .onDelete { draft.checklist.remove(atOffsets: $0) }
                    HStack {
                        Image(systemName: "plus.circle").foregroundStyle(palette.text3)
                        TextField("Add a step", text: $newItem)
                            .onSubmit {
                                let t = newItem.trimmingCharacters(in: .whitespaces)
                                guard !t.isEmpty else { return }
                                draft.checklist.append(ChecklistItem(title: t))
                                newItem = ""
                            }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if !isNew {
                    Section {
                        if draft.status.isClosed {
                            Button("Reopen") {
                                model.perform(.reopen, on: draft, undoable: false)
                                dismiss()
                            }
                        }
                        Button("Duplicate") {
                            var copy = draft
                            copy.id = UUID()
                            copy.status = .planned
                            copy.session = nil
                            copy.seriesID = nil
                            copy.occurrenceDay = nil
                            copy.start = draft.end
                            model.store.add(copy)
                            dismiss()
                        }
                        Button("Delete", role: .destructive) {
                            model.delete(draft)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.bg)
            .navigationTitle(isNew ? "New block" : "Edit block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if isNew { titleFocused = true } }
        }
        .presentationDetents([.large])
    }

    private var categoryPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(TaskCategory.allCases) { category in
                let selected = draft.category == category
                Button {
                    withAnimation(Motion.micro) { draft.category = category }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: category.symbol)
                            .font(.body)
                            .frame(width: 36, height: 36)
                            .background(category.color.opacity(selected ? 1 : 0.16), in: Circle())
                            .foregroundStyle(selected ? Color.white : category.color)
                        Text(category.displayName)
                            .font(.caption2)
                            .foregroundStyle(selected ? palette.text1 : palette.text2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.displayName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        var task = draft
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch reminder {
        case .defaultLead: task.remind = true; task.leadTimeMinutes = nil
        case .custom(let m): task.remind = true; task.leadTimeMinutes = m
        case .off: task.remind = false
        }
        if isNew, repeatChoice != .none {
            let cal = model.store.calendar
            let c = cal.dateComponents([.hour, .minute], from: task.start)
            let rule: RepeatRule = switch repeatChoice {
            case .daily: .daily
            case .weekdays: .weekdays
            default: .weekly(days: weeklyDays.isEmpty ? [cal.component(.weekday, from: task.start)] : weeklyDays)
            }
            let series = TaskSeries(
                title: task.title, notes: task.notes, category: task.category, durationMinutes: task.durationMinutes,
                leadTimeMinutes: task.leadTimeMinutes, remind: task.remind, checklistTitles: task.checklist.map(\.title),
                hour: c.hour ?? 9, minute: c.minute ?? 0, rule: rule, firstDay: DayKey(task.start, calendar: cal)
            )
            model.store.addSeries(series)
            model.showToast("Routine added · \(rule.label)", symbol: "repeat")
        } else if isNew {
            model.store.add(task)
            model.showToast("Added \(task.title)", symbol: "plus.circle.fill") { _ = model.store.delete(task.id, undoLabel: nil) }
        } else {
            model.store.update(task)
        }
        dismiss()
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    @Environment(\.palette) private var palette
    private let symbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = selection.contains(day)
                Button(symbols[day - 1]) {
                    if on { selection.remove(day) } else { selection.insert(day) }
                }
                .font(.footnote.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(on ? palette.now : palette.surface2, in: Circle())
                .foregroundStyle(on ? palette.onNow : palette.text1)
                .buttonStyle(.plain)
            }
        }
    }
}
