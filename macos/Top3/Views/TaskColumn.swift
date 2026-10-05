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
        VStack(alignment: .leading, spacing: 1) {
            if showHeader {
                HStack {
                    SectionHeader(title: list.title, detail: "\(tasks.count)")
                    Spacer()
                    AutoSortButton(list: list)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }

            ForEach(tasks) { task in
                VStack(spacing: 0) {
                    InsertionLine(visible: targetID == task.id)
                    TaskRow(task: task)
                        .draggable(TaskRef(id: task.id)) { DragPreview(title: task.title) }
                }
                .dropDestination(for: TaskRef.self) { items, _ in
                    drop(items, before: task.id)
                } isTargeted: { on in
                    if on { targetID = task.id } else if targetID == task.id { targetID = nil }
                }
                .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .trailing))))
            }

            VStack(spacing: 0) {
                InsertionLine(visible: endTargeted && !tasks.isEmpty)
                if tasks.isEmpty {
                    Text(endTargeted ? "Drop here" : "No tasks")
                        .font(Theme.secondary)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(endTargeted ? Color.accentColor : Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                } else {
                    Color.clear.frame(height: 18)
                }
                Button { model.newTask(in: list) } label: {
                    Label("Add task", systemImage: "plus").font(Theme.secondary)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .contentShape(Rectangle())
            .dropDestination(for: TaskRef.self) { items, _ in
                drop(items, before: nil)
            } isTargeted: { endTargeted = $0 }
        }
    }

    private func drop(_ items: [TaskRef], before: UUID?) -> Bool {
        guard let ref = items.first else { return false }
        withAnimation(.snappy) { model.move(ref.id, to: list, before: before, manual: true) }
        return true
    }
}

struct InsertionLine: View {
    let visible: Bool
    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 6)
            .opacity(visible ? 1 : 0)
    }
}

struct AutoSortButton: View {
    @Environment(AppModel.self) private var model
    let list: ListKind

    var body: some View {
        let on = model.isAutoSort(list)
        Button { withAnimation(.snappy) { model.toggleAutoSort(list) } } label: {
            HStack(spacing: 3) {
                Image(systemName: on ? "arrow.up.arrow.down" : "hand.point.up.left")
                Text(on ? "Auto" : "Manual")
            }
            .font(Theme.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(on ? Color.accentColor : Color.secondary)
            .background(Capsule().strokeBorder(on ? Color.accentColor.opacity(0.5) : Theme.hairline))
        }
        .buttonStyle(.plain)
        .help(on
            ? "Auto sort: due date, then priority, then shortest first. Dragging a task switches to manual."
            : "Manual order. Click to auto sort by due date, priority, then shortest first.")
    }
}
