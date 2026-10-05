import SwiftUI

/// A list of draggable tasks that accepts drops between rows (reorder) and at the end (append).
struct TaskColumn: View {
    @Environment(AppModel.self) private var model
    let list: ListKind
    let tasks: [TaskItem]
    var showHeader = true

    @State private var targetID: UUID?
    @State private var endTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                HStack {
                    SectionLabel(title: list.title, detail: "\(tasks.count)")
                    Spacer()
                    AutoSortControl(list: list)
                }
                .padding(.leading, Theme.Space.s)
                .frame(height: Theme.Size.row)
            }

            ForEach(tasks) { task in
                VStack(spacing: 0) {
                    InsertionLine(visible: targetID == task.id)
                    TaskRow(task: task, showDivider: task.id != tasks.last?.id)
                        .draggable(TaskRef(id: task.id)) { DragPreview(title: task.title) }
                }
                .dropDestination(for: TaskRef.self) { items, _ in
                    drop(items, before: task.id)
                } isTargeted: { on in
                    if on { targetID = task.id } else if targetID == task.id { targetID = nil }
                }
                .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 0) {
                InsertionLine(visible: endTargeted && !tasks.isEmpty)
                if tasks.isEmpty {
                    EmptyLine(text: endTargeted ? "Drop here" : "No tasks")
                        .padding(.leading, Theme.Space.s)
                        .rowFill(hovering: endTargeted)
                }
                NewTaskButton { model.newTask(in: list) }
            }
            .contentShape(Rectangle())
            .dropDestination(for: TaskRef.self) { items, _ in
                drop(items, before: nil)
            } isTargeted: { on in
                withAnimation(Theme.Motion.hover) { endTargeted = on }
            }
        }
    }

    private func drop(_ items: [TaskRef], before: UUID?) -> Bool {
        guard let ref = items.first else { return false }
        withAnimation(Theme.Motion.list) { model.move(ref.id, to: list, before: before, manual: true) }
        return true
    }
}

struct NewTaskButton: View {
    var title = "New task"
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                Icon(.add, size: Theme.Size.dragHandle)
                    .frame(width: Theme.Size.checkbox)
                Text(title).font(Theme.Fonts.small)
                Spacer()
            }
            .foregroundStyle(hovering ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
            .padding(.leading, Theme.Space.s + Theme.Size.dragHandle + Theme.Space.s)
            .frame(height: Theme.Size.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
    }
}

/// Small icon button with a tiny label showing the list's sort mode.
struct AutoSortControl: View {
    @Environment(AppModel.self) private var model
    let list: ListKind

    var body: some View {
        let on = model.isAutoSort(list)
        IconButton(icon: on ? .autoSort : .manual,
                   help: on
                       ? "Auto sort: due date, then priority, then shortest first. Dragging a task switches to manual."
                       : "Manual order. Click to auto sort by due date, priority, then shortest first.",
                   label: on ? "Auto" : "Manual",
                   active: on) {
            withAnimation(Theme.Motion.list) { model.toggleAutoSort(list) }
        }
    }
}
