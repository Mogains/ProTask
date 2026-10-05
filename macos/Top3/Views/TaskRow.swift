import SwiftUI

/// One task on a single 32pt line. Hover reveals a drag handle, the Top 3 star and an actions menu.
struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    /// In a Top 3 slot the row stays put after checking.
    var inTopSlot = false
    var showDivider = true
    var showHandle = true

    @State private var checking = false
    @State private var hovering = false

    var body: some View {
        let selected = model.selectedTaskID == task.id
        let checked = task.isCompleted || checking

        HStack(spacing: Theme.Space.s) {
            if showHandle {
                Icon(.drag, size: Theme.Size.icon)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: Theme.Size.dragHandle)
                    .opacity(hovering && !task.isCompleted ? 1 : 0)
                    .help("Drag to move")
            }

            if task.isIdea {
                Icon(.idea)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: Theme.Size.checkbox)
            } else {
                Button(action: toggle) { Checkbox(checked: checked) }
                    .buttonStyle(.plain)
                    .help(checked ? "Mark as not done" : "Mark as done")
            }

            Text(task.title)
                .font(Theme.Fonts.body)
                .foregroundStyle(checked ? Theme.Palette.textTertiary : Theme.Palette.text)
                .strikethrough(checked, color: Theme.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            if !task.notes.isEmpty {
                Icon(.notes, size: Theme.Size.dragHandle)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .help(task.notes)
            }

            Spacer(minLength: Theme.Space.s)

            RowMeta(task: task)

            trailing(selected: selected)
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: Theme.Size.row)
        .rowFill(hovering: hovering, selected: selected)
        .overlay(alignment: .bottom) {
            if showDivider { Hairline().padding(.leading, Theme.Space.s) }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .onTapGesture(count: 2) { model.edit(task) }
        .simultaneousGesture(TapGesture().onEnded { model.selectedTaskID = task.id })
        .contextMenu { TaskMenu(task: task) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func trailing(selected: Bool) -> some View {
        let reveal = hovering || selected
        if task.isIdea {
            HStack(spacing: 0) {
                IconButton(icon: .send, help: "Send to Have to do", label: "Have") { withAnimation(Theme.Motion.list) { model.send(task, to: .haveTo) } }
                IconButton(icon: .send, help: "Send to Nice to do", label: "Nice") { withAnimation(Theme.Motion.list) { model.send(task, to: .niceTo) } }
                IconButton(icon: .later, help: "Keep in Parking Lot, remind again in an hour") { model.snooze(task) }
                IconButton(icon: .delete, help: "Delete") { withAnimation(Theme.Motion.list) { model.delete(task) } }
            }
            .opacity(reveal ? 1 : 0)
        } else if task.isWaiting {
            HStack(spacing: 0) {
                IconButton(icon: .done, help: "Mark received", label: "Received") { withAnimation(Theme.Motion.list) { model.receive(task) } }
                IconButton(icon: .later, help: "Snooze the follow-up 1 day", label: "1 day") { model.snoozeFollowUp(task) }
                IconButton(icon: .send, help: "Move to Have to do", label: "Have") { withAnimation(Theme.Motion.list) { model.send(task, to: .haveTo) } }
                ActionsMenu(help: "More actions") { TaskMenu(task: task) }
            }
            .opacity(reveal ? 1 : 0)
        } else {
            HStack(spacing: 0) {
                if !task.isCompleted {
                    IconButton(icon: .today,
                               help: task.topSlot != nil ? "Remove from Top 3" : "Add to Top 3",
                               active: task.topSlot != nil) {
                        withAnimation(Theme.Motion.list) { model.togglePin(task) }
                    }
                    .opacity(reveal || task.topSlot != nil ? 1 : 0)
                }
                ActionsMenu(help: "More actions") { TaskMenu(task: task) }
                    .opacity(reveal ? 1 : 0)
            }
        }
    }

    private func toggle() {
        model.selectedTaskID = task.id
        if task.isCompleted {
            withAnimation(Theme.Motion.list) { model.setCompleted(task, false) }
            return
        }
        guard !checking else { return }
        checking = true
        // Let the check draw, then the row leaves for Done.
        DispatchQueue.main.asyncAfter(deadline: .now() + (inTopSlot ? 0 : Theme.Motion.checkDelay)) {
            withAnimation(Theme.Motion.list) { model.setCompleted(task, true) }
            checking = false
        }
    }
}

/// Due date, priority and estimate as small muted text.
struct RowMeta: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if task.isCompleted, let at = task.completedAt {
                Text("Done \(Fmt.time(at))")
            } else if task.isWaiting {
                if !task.waitingOn.isEmpty { Text(task.waitingOn) }
                if let f = task.followUpDate {
                    let due = DayKey.dateKey(f) <= model.today
                    Text(due ? "follow up" : "Follow up \(f.formatted(.dateTime.month(.abbreviated).day()))")
                        .foregroundStyle(due ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
                }
            } else if task.isIdea {
                Text("Added \(Fmt.time(task.createdAt))")
                if let r = task.remindAt {
                    Text(r > Date() ? "Reminds \(Fmt.time(r))" : "Reminder sent")
                }
            } else {
                if task.priority != .medium {
                    Icon(task.priority == .high ? .priority3 : .priority1, size: Theme.Size.icon)
                        .foregroundStyle(task.priority == .high ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
                        .help("\(task.priority.title) priority")
                }
                if let due = Fmt.due(task, today: model.today) {
                    HStack(spacing: Theme.Space.xs) {
                        Icon(.due, size: Theme.Size.dragHandle)
                        Text(due.text)
                    }
                    .foregroundStyle(due.overdue ? Theme.Palette.text : Theme.Palette.textSecondary)
                }
                if let rule = task.recurrence {
                    Icon(.repeat, size: Theme.Size.dragHandle).help("Repeats: \(rule.summary)")
                }
                if task.actualSeconds >= 60 {
                    let actual = Fmt.minutes(task.actualSeconds / 60) ?? ""
                    Text(task.estimateMinutes.flatMap(Fmt.minutes).map { "\(actual) / \($0)" } ?? "\(actual) spent")
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .help("Actual focus time / estimate")
                } else if let est = Fmt.minutes(task.estimateMinutes) {
                    Text(est).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .font(Theme.Fonts.secondary)
        .foregroundStyle(Theme.Palette.textTertiary)
        .lineLimit(1)
        .fixedSize()
    }
}

struct TaskMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Button("Edit…") { model.edit(task) }
        if task.isWaiting && !task.isCompleted {
            Button("Mark Received") { model.receive(task) }
            Button("Snooze Follow-up 1 Day") { model.snoozeFollowUp(task) }
            Button("Move to Have to do") { model.send(task, to: .haveTo) }
        } else if task.isIdea {
            Button("Send to Have to do") { model.send(task, to: .haveTo) }
            Button("Send to Nice to do") { model.send(task, to: .niceTo) }
            Button("Keep in Parking Lot") { model.snooze(task) }
        } else {
            Button(task.isCompleted ? "Mark as Not Done" : "Mark as Done") { model.setCompleted(task, !task.isCompleted) }
            if !task.isCompleted {
                Menu("Focus") {
                    Button("25 minutes") { model.startFocus(on: task, minutes: 25) }
                    Button("50 minutes") { model.startFocus(on: task, minutes: 50) }
                    Button("Custom…") { model.customFocusRequest = CustomFocusRequest(taskID: task.id) }
                }
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
                    ForEach(ListKind.taskLists + [.waitingOn]) { l in
                        Button(l.title) { model.send(task, to: l) }.disabled(l == task.list && task.topSlot == nil)
                    }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(task) }
    }
}
