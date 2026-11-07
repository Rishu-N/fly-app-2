import PlannerCore
import SwiftUI

/// Review card for staged changes: Add / Move / Edit / Remove rows (symbol + word, never colour
/// alone), per-row checkboxes, Apply / Discard, then Undo for the whole set.
struct ProposalCard: View {
    let proposal: Proposal
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var applyTrigger = 0

    private var session: AssistantSession { model.assistantService.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(stateLabel, color: stateColor)
                Spacer()
                Text("\(proposal.items.count) change\(proposal.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(palette.text3)
            }
            if !proposal.summary.isEmpty {
                Text(proposal.summary)
                    .font(.headline)
                    .foregroundStyle(palette.text1)
            }
            VStack(spacing: 0) {
                ForEach(proposal.items) { item in
                    ProposalRow(item: item, editable: proposal.state == .pending) {
                        session.toggle(item.id, inProposal: proposal.id)
                    }
                    if item.id != proposal.items.last?.id {
                        Divider().overlay(palette.separator)
                    }
                }
            }
            .background(palette.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            actions
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(proposal.state == .pending ? palette.now.opacity(0.5) : palette.separator, lineWidth: 1))
        .sensoryFeedback(.success, trigger: applyTrigger)
        .animation(Motion.snappy, value: proposal.state)
    }

    @ViewBuilder
    private var actions: some View {
        switch proposal.state {
        case .pending:
            HStack(spacing: 10) {
                Button {
                    applyTrigger += 1
                    withAnimation(Motion.glide) { session.apply(proposal.id) }
                } label: {
                    Text(proposal.selectedCount == proposal.items.count ? "Apply" : "Apply \(proposal.selectedCount)")
                }
                .buttonStyle(PillButtonStyle(fill: palette.now, foreground: palette.onNow, height: 46))
                .disabled(proposal.selectedCount == 0)
                Button("Discard") { session.discard(proposal.id) }
                    .buttonStyle(PillButtonStyle(fill: palette.surface2, foreground: palette.text1, height: 46))
            }
        case .applied(let count, _):
            HStack {
                Label("Applied \(count) change\(count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.success)
                Spacer()
                Button("Undo") { withAnimation(Motion.glide) { session.undo(proposal.id) } }
                    .font(.subheadline.weight(.semibold))
            }
        case .discarded:
            Label("Discarded — nothing changed", systemImage: "xmark.circle")
                .font(.subheadline)
                .foregroundStyle(palette.text3)
        case .undone:
            Label("Undone", systemImage: "arrow.uturn.backward.circle")
                .font(.subheadline)
                .foregroundStyle(palette.text3)
        }
    }

    private var stateLabel: String {
        switch proposal.state {
        case .pending: "Ready to review"
        case .applied: "Applied"
        case .discarded: "Discarded"
        case .undone: "Undone"
        }
    }

    private var stateColor: Color {
        switch proposal.state {
        case .pending: palette.now
        case .applied: palette.success
        default: palette.text3
        }
    }
}

private struct ProposalRow: View {
    let item: ProposalItem
    let editable: Bool
    let toggle: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let task = item.after ?? item.before
        HStack(alignment: .top, spacing: 12) {
            if editable {
                Button(action: toggle) {
                    Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(item.isSelected ? palette.now : palette.text3)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isSelected ? "Included" : "Excluded")
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Label(kindLabel, systemImage: kindSymbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(kindColor)
                    if let task { CategoryDot(category: task.category, size: 6) }
                }
                Text(task?.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(item.kind == .remove)
                    .foregroundStyle(palette.text1)
                Text(timeLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.text2)
                ForEach(item.notes, id: \.self) { note in
                    Label(note, systemImage: note.hasPrefix("Overlaps") || note == "In the past" ? "exclamationmark.triangle" : "info.circle")
                        .font(.caption2)
                        .foregroundStyle(note.hasPrefix("Overlaps") || note == "In the past" ? palette.warning : palette.text3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .opacity(item.isSelected || !editable ? 1 : 0.45)
        .accessibilityElement(children: .combine)
    }

    private var kindLabel: String {
        switch item.kind {
        case .add: "Add"
        case .move: "Move"
        case .edit: "Edit"
        case .remove: "Remove"
        case .addRoutine: "Routine"
        }
    }

    private var kindSymbol: String {
        switch item.kind {
        case .add: "plus.circle.fill"
        case .move: "arrow.right.circle.fill"
        case .edit: "pencil.circle.fill"
        case .remove: "minus.circle.fill"
        case .addRoutine: "repeat.circle.fill"
        }
    }

    private var kindColor: Color {
        switch item.kind {
        case .add, .addRoutine: palette.success
        case .move, .edit: palette.now
        case .remove: palette.danger
        }
    }

    private var timeLine: String {
        let day: (Date) -> String = { date in
            Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).day())
        }
        switch item.kind {
        case .move:
            guard let b = item.before, let a = item.after else { return "" }
            let sameDay = Calendar.current.isDate(b.start, inSameDayAs: a.start)
            let from = "\(b.start.clockString())"
            let to = sameDay ? a.windowString() : "\(day(a.start)) \(a.windowString())"
            return "\(from) → \(to) · \(formatDuration(a.durationMinutes))"
        case .remove:
            guard let b = item.before else { return "" }
            return "\(day(b.start)) \(b.windowString())"
        case .addRoutine:
            guard let a = item.after else { return "" }
            return "From \(day(a.start)) \(a.windowString())"
        default:
            guard let a = item.after else { return "" }
            return "\(day(a.start)) \(a.windowString()) · \(formatDuration(a.durationMinutes))"
        }
    }
}

/// Fill-in form for a prompt template: one field per placeholder, then an editable preview.
struct TemplateFormView: View {
    let template: PromptTemplate
    let onSend: (String) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var edited: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(template.placeholders, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PromptTemplate.label(for: key)).font(.caption).foregroundStyle(palette.text2)
                            TextField(template.hints[key] ?? template.defaults[key] ?? "", text: binding(for: key))
                        }
                    }
                } header: {
                    Label(template.subtitle, systemImage: template.symbol)
                }
                Section("Message") {
                    TextField("", text: Binding(get: { edited ?? template.render(values) }, set: { edited = $0 }), axis: .vertical)
                        .lineLimit(3...10)
                        .font(.callout)
                }
            }
            .navigationTitle(template.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { onSend(edited ?? template.render(values)) }.fontWeight(.semibold)
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? template.defaults[key] ?? "" },
            set: { values[key] = $0; edited = nil }
        )
    }
}
