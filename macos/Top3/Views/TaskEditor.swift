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
    @State private var detectDates = true
    @State private var repeatKind: RecurrenceRule.Kind?
    @State private var repeatInterval = "1"
    @State private var repeatUnit: RecurrenceRule.Unit = .days
    @State private var repeatDays: Set<Int> = []
    @State private var waitingOn = ""
    @State private var tagsText = ""
    @State private var hasFollowUp = false
    @State private var followUp = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: Date()))!
    @State private var originalTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SmartTaskField(placeholder: "Task title", text: $title, detectDates: $detectDates, font: Theme.Fonts.input,
                               bordered: false, focusOnAppear: true, onSubmit: save)
                InputField(placeholder: "Add notes", text: $notes, font: Theme.Fonts.small, bordered: false, axis: .vertical)
                    .lineLimit(1...6)
            }
            .padding(Theme.Space.l)

            Hairline()

            VStack(spacing: 0) {
                PropertyRow(label: "List") {
                    Segments(options: listChoices, selection: $list) { $0.title }
                }
                if list == .waitingOn {
                    PropertyRow(label: "Waiting on") {
                        InputField(placeholder: "Who (optional)", text: $waitingOn, font: Theme.Fonts.small)
                    }
                    PropertyRow(label: "Follow up") {
                        if hasFollowUp {
                            DatePicker("Follow up", selection: $followUp, displayedComponents: .date)
                                .labelsHidden().datePickerStyle(.field).font(Theme.Fonts.small)
                            Spacer()
                            Button("Clear") { hasFollowUp = false }.buttonStyle(.ghost)
                        } else {
                            Button("Set date") { hasFollowUp = true }.buttonStyle(.ghost)
                        }
                    }
                } else if list != .parkingLot {
                    PropertyRow(label: "Priority") {
                        Segments(options: Priority.allCases, selection: $priority) { $0.title }
                    }
                    PropertyRow(label: "Due") { dueControls }
                    PropertyRow(label: "Estimate") { estimateControls }
                    PropertyRow(label: "Tags") {
                        InputField(placeholder: "work errands", text: $tagsText, font: Theme.Fonts.small)
                    }
                    PropertyRow(label: "Repeat") {
                        Segments(options: [nil] + RecurrenceRule.Kind.allCases.map { Optional($0) }, selection: $repeatKind) {
                            $0?.title ?? "None"
                        }
                    }
                    if repeatKind == .custom {
                        PropertyRow(label: "") { customRepeatControls }
                    }
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

    private var customRepeatControls: some View {
        HStack(spacing: Theme.Space.xs) {
            Text("Every").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
            TextField("", text: $repeatInterval)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .font(Theme.Fonts.small)
                .multilineTextAlignment(.center)
                .frame(width: Theme.Size.iconButton)
                .frame(height: Theme.Size.iconButton)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
            Segments(options: RecurrenceRule.Unit.allCases, selection: $repeatUnit) { $0.rawValue }
            if repeatUnit == .weeks {
                ForEach(1...7, id: \.self) { day in
                    let on = repeatDays.contains(day)
                    Button { if on { repeatDays.remove(day) } else { repeatDays.insert(day) } } label: {
                        Text(RecurrenceRule.weekdayLetters[day - 1])
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(on ? Theme.Palette.text : Theme.Palette.textTertiary)
                            .frame(width: Theme.Size.slotNumber + Theme.Space.xs, height: Theme.Size.iconButton)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(on ? Theme.Palette.selected : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var draftRecurrence: RecurrenceRule? {
        guard let kind = repeatKind else { return nil }
        return RecurrenceRule(kind: kind, interval: max(Int(repeatInterval) ?? 1, 1), unit: repeatUnit, weekdays: repeatDays.sorted())
    }

    private var listChoices: [ListKind] {
        request.task?.isIdea == true ? ListKind.allCases : ListKind.taskLists + [.waitingOn]
    }

    private func load() {
        list = request.list == .parkingLot && request.task == nil ? .haveTo : request.list
        if let t = request.task {
            title = t.title
            originalTitle = t.title
            notes = t.notes
            list = t.list
            priority = t.priority
            if let d = t.dueDate {
                hasDue = true
                dueDate = d
                hasTime = t.hasDueTime
            }
            estimate = t.estimateMinutes.map(String.init) ?? ""
            waitingOn = t.waitingOn
            tagsText = t.tags.joined(separator: " ")
            if let f = t.followUpDate { hasFollowUp = true; followUp = f }
            if let r = t.recurrence {
                repeatKind = r.kind
                repeatInterval = String(r.interval)
                repeatUnit = r.unit
                repeatDays = Set(r.weekdays)
            }
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Natural language in the title fills the fields (only when the title was typed or changed here).
        var finalTitle = title
        if list != .parkingLot && list != .waitingOn && title != originalTitle {
            let p = TaskParser.parse(title, detectDates: detectDates)
            finalTitle = p.title
            if let d = p.dueDate { hasDue = true; dueDate = d; hasTime = p.hasDueTime }
            if let pr = p.priority { priority = pr }
            if let m = p.estimateMinutes { estimate = String(m) }
            if !p.tags.isEmpty { tagsText = (tagsText.split(separator: " ").map(String.init) + p.tags).joined(separator: " ") }
        }
        var due: Date? = nil
        if hasDue && list != .parkingLot && list != .waitingOn {
            due = hasTime ? dueDate : Calendar.current.startOfDay(for: dueDate)
        }
        let draft = TaskDraft(title: finalTitle, notes: notes, list: list, priority: priority, dueDate: due,
                              hasDueTime: hasDue && hasTime, estimateMinutes: Int(estimate.trimmingCharacters(in: .whitespaces)),
                              recurrence: draftRecurrence, waitingOn: waitingOn,
                              followUpDate: hasFollowUp ? Calendar.current.startOfDay(for: followUp) : nil,
                              tags: tagsText.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init))
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
