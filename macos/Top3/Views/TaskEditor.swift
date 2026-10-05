import SwiftUI

struct TaskEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: EditorRequest

    @State private var title = ""
    @State private var notes = ""
    @State private var list: ListKind = .haveTo
    @State private var priority: Priority = .medium
    @State private var hasDue = false
    @State private var dueDate = Calendar.current.startOfDay(for: Date())
    @State private var hasTime = false
    @State private var estimate = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                InputField(placeholder: "Task title", text: $title, font: Theme.Fonts.input, bordered: false,
                           focusOnAppear: true, onSubmit: save)
                InputField(placeholder: "Add notes", text: $notes, font: Theme.Fonts.small, bordered: false, axis: .vertical)
                    .lineLimit(1...6)
            }
            .padding(Theme.Space.l)

            Hairline()

            VStack(spacing: 0) {
                PropertyRow(label: "List") {
                    Segments(options: listChoices, selection: $list) { $0.title }
                }
                if list != .parkingLot {
                    PropertyRow(label: "Priority") {
                        Segments(options: Priority.allCases, selection: $priority) { $0.title }
                    }
                    PropertyRow(label: "Due") { dueControls }
                    PropertyRow(label: "Estimate") { estimateControls }
                }
            }
            .padding(.vertical, Theme.Space.s)

            Hairline()

            HStack(spacing: Theme.Space.xs) {
                if let task = request.task {
                    Button("Delete") {
                        dismiss()
                        model.delete(task)
                    }
                    .buttonStyle(.ghost)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.ghost)
                    .keyboardShortcut(.cancelAction)
                Button(request.task == nil ? "Add task" : "Save") { save() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Theme.Space.m)
        }
        .frame(width: Theme.Size.sheetWidth)
        .font(Theme.Fonts.body)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .onAppear(perform: load)
    }

    @ViewBuilder private var dueControls: some View {
        if hasDue {
            HStack(spacing: Theme.Space.s) {
                DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .font(Theme.Fonts.small)
                if hasTime {
                    DatePicker("Time", selection: $dueDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .font(Theme.Fonts.small)
                    IconButton(icon: .close, help: "Remove time") { withAnimation(Theme.Motion.standard) { hasTime = false } }
                } else {
                    Button("Add time") { withAnimation(Theme.Motion.standard) { hasTime = true } }.buttonStyle(.ghost)
                }
                Spacer()
                Button("Clear") { withAnimation(Theme.Motion.standard) { hasDue = false; hasTime = false } }.buttonStyle(.ghost)
            }
        } else {
            Button("Set date") { withAnimation(Theme.Motion.standard) { hasDue = true } }.buttonStyle(.ghost)
        }
    }

    private var estimateControls: some View {
        HStack(spacing: Theme.Space.xs) {
            TextField("", text: $estimate, prompt: Text("0").foregroundStyle(Theme.Palette.textTertiary))
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .font(Theme.Fonts.small)
                .multilineTextAlignment(.trailing)
                .frame(width: Theme.Size.estimateField)
                .padding(.horizontal, Theme.Space.s)
                .frame(height: Theme.Size.iconButton)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
            Text("min").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
            ForEach([15, 30, 60], id: \.self) { m in
                Button("\(m)") { estimate = String(m) }.buttonStyle(.ghost)
            }
        }
    }

    private var listChoices: [ListKind] {
        request.task?.isIdea == true ? ListKind.allCases : ListKind.taskLists
    }

    private func load() {
        list = request.list == .parkingLot && request.task == nil ? .haveTo : request.list
        if let t = request.task {
            title = t.title
            notes = t.notes
            list = t.list
            priority = t.priority
            if let d = t.dueDate {
                hasDue = true
                dueDate = d
                hasTime = t.hasDueTime
            }
            estimate = t.estimateMinutes.map(String.init) ?? ""
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var due: Date? = nil
        if hasDue && list != .parkingLot {
            due = hasTime ? dueDate : Calendar.current.startOfDay(for: dueDate)
        }
        let draft = TaskDraft(title: title, notes: notes, list: list, priority: priority, dueDate: due,
                              hasDueTime: hasDue && hasTime, estimateMinutes: Int(estimate.trimmingCharacters(in: .whitespaces)))
        if let t = request.task { model.update(t, with: draft) } else { model.addTask(draft) }
        dismiss()
    }
}

private struct PropertyRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(label)
                .font(Theme.Fonts.small)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: Theme.Size.propertyLabel, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(minHeight: Theme.Size.row)
    }
}

/// Inline option picker: ghost buttons, the chosen one gets a subtle fill.
struct Segments<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button { withAnimation(Theme.Motion.hover) { selection = option } } label: {
                    Text(title(option))
                        .font(Theme.Fonts.small)
                        .foregroundStyle(on ? Theme.Palette.text : Theme.Palette.textSecondary)
                        .padding(.horizontal, Theme.Space.s)
                        .frame(height: Theme.Size.iconButton)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(on ? Theme.Palette.selected : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct QuickParkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InputField(placeholder: "Park an idea…", text: $text, font: Theme.Fonts.input, leadingIcon: .quickAdd,
                       bordered: false, focusOnAppear: true) {
                if model.addIdea(text) { model.showToast("Parked. Reminder in an hour.") }
                dismiss()
            }
            .padding(Theme.Space.l)
            Hairline()
            HStack {
                Text("Goes to the Parking Lot and reminds you in an hour.")
                Spacer()
                Text("↩ to save   esc to cancel")
            }
            .font(Theme.Fonts.secondary)
            .foregroundStyle(Theme.Palette.textTertiary)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            Button("") { dismiss() }.keyboardShortcut(.cancelAction).hidden().frame(width: 0, height: 0)
        }
        .frame(width: Theme.Size.quickAddWidth)
        .foregroundStyle(Theme.Palette.text)
    }
}
