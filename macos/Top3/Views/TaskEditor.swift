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
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Title", text: $title, prompt: Text("What needs doing?"))
                    .focused($titleFocused)
                TextField("Notes", text: $notes, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(2...6)
                Picker("List", selection: $list) {
                    ForEach(listChoices) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if list != .parkingLot {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Due date", isOn: $hasDue.animation(.snappy))
                    if hasDue {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                        Toggle("Time", isOn: $hasTime.animation(.snappy))
                        if hasTime {
                            DatePicker("At", selection: $dueDate, displayedComponents: .hourAndMinute)
                        }
                    }
                    LabeledContent("Estimate") {
                        HStack(spacing: 6) {
                            TextField("Minutes", text: $estimate, prompt: Text("min"))
                                .labelsHidden()
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                            ForEach([15, 30, 60], id: \.self) { m in
                                Button("\(m)") { estimate = String(m) }.controlSize(.small)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .font(Theme.body)

            HStack {
                if let task = request.task {
                    Button("Delete", role: .destructive) {
                        dismiss()
                        model.delete(task)
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.task == nil ? "Add Task" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(width: 440)
        .onAppear(perform: load)
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
        titleFocused = true
    }

    private func save() {
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

struct QuickParkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Park an idea", systemImage: "lightbulb").font(Theme.bodyMedium)
            TextField("Type and press Return", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.body)
                .focused($focused)
                .onSubmit {
                    if model.addIdea(text) { model.showToast("Parked. Reminder in an hour.") }
                    dismiss()
                }
            Text("Goes to the Parking Lot. You'll get a reminder in an hour to sort it.")
                .font(Theme.secondary).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear { focused = true }
    }
}
