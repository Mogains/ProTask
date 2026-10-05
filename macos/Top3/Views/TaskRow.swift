import SwiftUI

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    /// In a Top 3 slot the row stays put after checking.
    var inTopSlot = false

    @State private var checking = false
    @State private var hovering = false

    var body: some View {
        let selected = model.selectedTaskID == task.id
        let checked = task.isCompleted || checking

        HStack(alignment: .top, spacing: 8) {
            if task.isIdea {
                Image(systemName: "lightbulb")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)
            } else {
            Button(action: toggle) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: checked)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .help(checked ? "Mark as not done" : "Mark as done")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(Theme.body)
                    .strikethrough(checked, color: .secondary)
                    .foregroundStyle(checked ? .secondary : .primary)
                    .lineLimit(2)
                TaskMeta(task: task)
            }

            Spacer(minLength: 4)

            if !task.isCompleted && !task.isIdea && (hovering || selected || task.topSlot != nil) {
                Button { model.togglePin(task) } label: {
                    Image(systemName: task.topSlot != nil ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(task.topSlot != nil ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .help(task.topSlot != nil ? "Remove from Top 3" : "Add to Top 3")
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Theme.rowSelected : hovering ? Theme.rowHover : .clear))
        .contentShape(Rectangle())
        .opacity(checking && !inTopSlot ? 0.45 : 1)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.edit(task) }
        .simultaneousGesture(TapGesture().onEnded { model.selectedTaskID = task.id })
        .contextMenu { TaskMenu(task: task) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle() {
        model.selectedTaskID = task.id
        if task.isCompleted {
            withAnimation(.snappy) { model.setCompleted(task, false) }
            return
        }
        guard !checking else { return }
        withAnimation(.snappy(duration: 0.2)) { checking = true }
        // Let the check land before the row slides away to Done.
        DispatchQueue.main.asyncAfter(deadline: .now() + (inTopSlot ? 0.15 : 0.45)) {
            withAnimation(.easeOut(duration: 0.25)) { model.setCompleted(task, true) }
            checking = false
        }
    }
}

struct TaskMeta: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        let due = Fmt.due(task, today: model.today)
        let est = Fmt.minutes(task.estimateMinutes)
        let showPriority = task.priority != .medium
        if task.isIdea || task.isCompleted || due != nil || est != nil || showPriority || !task.notes.isEmpty {
            HStack(spacing: 9) {
                if task.isCompleted, let at = task.completedAt {
                    item("checkmark", "Done \(Fmt.time(at))")
                } else if task.isIdea {
                    item("clock", "Added \(Fmt.time(task.createdAt))")
                    if let r = task.remindAt {
                        item(r > Date() ? "bell" : "bell.slash", r > Date() ? "Reminder \(Fmt.time(r))" : "Reminder sent")
                    }
                }
                if !task.isIdea {
                    if showPriority { item(task.priority == .high ? "arrow.up" : "arrow.down", task.priority.title) }
                    if let due {
                        item(due.overdue && !task.isCompleted ? "exclamationmark.circle" : "calendar", due.text)
                            .foregroundStyle(due.overdue && !task.isCompleted ? Color.primary : Color.secondary)
                    }
                    if let est { item("timer", est) }
                }
                if !task.notes.isEmpty { Image(systemName: "text.alignleft").help(task.notes) }
            }
            .font(Theme.secondary)
            .foregroundStyle(.secondary)
            .imageScale(.small)
        }
    }

    private func item(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text)
        }
    }
}

struct TaskMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Button("Edit…") { model.edit(task) }
        if task.isIdea {
            Button("Send to Have to do") { model.send(task, to: .haveTo) }
            Button("Send to Nice to do") { model.send(task, to: .niceTo) }
            Button("Keep in Parking Lot (remind in 1 hour)") { model.snooze(task) }
        } else {
            Button(task.isCompleted ? "Mark as Not Done" : "Mark as Done") { model.setCompleted(task, !task.isCompleted) }
            if !task.isCompleted {
                Menu("Top 3") {
                    ForEach(Top3Planner.slots, id: \.self) { n in
                        Button("Slot \(n)") { model.pin(task.id, slot: n) }
                    }
                    if task.topSlot != nil {
                        Divider()
                        Button("Remove from Top 3") { model.unpin(task) }
                    }
                }
                Menu("Move to") {
                    ForEach(ListKind.taskLists) { l in
                        Button(l.title) { model.send(task, to: l) }.disabled(l == task.list && task.topSlot == nil)
                    }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(task) }
    }
}
