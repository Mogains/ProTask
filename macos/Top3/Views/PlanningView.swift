import SwiftData
import SwiftUI

/// Full-window morning planning: rolled-over picks, overdue and due-today tasks, today's calendar.
/// Pick the Top 3 by clicking, or with arrow keys and 1/2/3. Return starts the day, Esc skips it.
struct PlanningView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    @State private var highlight = 0

    var body: some View {
        let groups = candidateGroups
        let flat = groups.flatMap(\.tasks)
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Text("Plan your day").font(Theme.Fonts.bodyMedium)
                Text((DayKey.date(from: model.today) ?? Date()).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(Theme.Fonts.small)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Button("Skip for today") { model.finishPlanning() }.buttonStyle(.ghost)
                Button("Start the day") { model.finishPlanning() }.buttonStyle(.primary)
            }
            .padding(.leading, Theme.Size.trafficLights)
            .padding(.trailing, Theme.Space.l)
            .frame(height: Theme.Size.header)
            .background(WindowDragArea())
            Hairline()

            ScrollView {
                HStack(alignment: .top, spacing: Theme.Space.xxl) {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        Top3Block(pins: model.pinned(in: tasks))
                        if flat.isEmpty {
                            EmptyLine(text: "Nothing rolled over or due today. Pick from your lists or start the day.")
                        }
                        ForEach(groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                SectionLabel(title: group.title, detail: "\(group.tasks.count)")
                                    .padding(.leading, Theme.Space.s)
                                    .frame(height: Theme.Size.row)
                                ForEach(group.tasks) { t in
                                    PlanRow(task: t, highlighted: flat.firstIndex(of: t) == highlight) {
                                        withAnimation(Theme.Motion.list) { model.togglePin(t) }
                                    }
                                }
                            }
                        }
                        Text("↑ ↓ to move   1 2 3 to place   return to start the day   esc to skip")
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .frame(maxWidth: Theme.Size.contentMaxWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        SectionLabel(title: "Calendar").frame(height: Theme.Size.row)
                        CalendarAgenda(compact: true)
                    }
                    .frame(width: Theme.Size.panelWidth, alignment: .leading)
                }
                .padding(.horizontal, Theme.Space.xxl)
                .padding(.vertical, Theme.Space.xl)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background)
        .ignoresSafeArea()
        .background(KeyMonitor(active: model.editor == nil && !model.showPalette) { event in
            switch event.keyCode {
            case KeyMonitor.down: highlight = min(highlight + 1, max(flat.count - 1, 0)); return true
            case KeyMonitor.up: highlight = max(highlight - 1, 0); return true
            case KeyMonitor.returnKey: model.finishPlanning(); return true
            case KeyMonitor.escape: model.finishPlanning(); return true
            default:
                guard let ch = event.charactersIgnoringModifiers, let slot = Int(ch), (1...3).contains(slot),
                      flat.indices.contains(highlight) else { return false }
                withAnimation(Theme.Motion.list) { model.pin(flat[highlight].id, slot: slot) }
                return true
            }
        })
    }

    private struct Group { let title: String; let tasks: [TaskItem] }

    private var candidateGroups: [Group] {
        let open = tasks.filter { !$0.isCompleted && !$0.isIdea }
        let rolledIDs = Set(Rollover.decode(model.dayLog(model.today).rolledOverRaw))
        let rolled = open.filter { rolledIDs.contains($0.id) }
        let used = Set(rolled.map(\.id))
        let overdue = TaskSorting.sorted(open.filter { t in
            !used.contains(t.id) && (t.dueDate.map { DayKey.dateKey($0) < model.today } ?? false)
        })
        let dueToday = TaskSorting.sorted(open.filter { t in
            !used.contains(t.id) && (t.dueDate.map { DayKey.dateKey($0) == model.today } ?? false)
        })
        return [Group(title: "Rolled over from yesterday", tasks: rolled),
                Group(title: "Overdue", tasks: overdue),
                Group(title: "Due today", tasks: dueToday)].filter { !$0.tasks.isEmpty }
    }
}

private struct PlanRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    let highlighted: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Space.s) {
                Text(task.topSlot.map(String.init) ?? "")
                    .font(Theme.Fonts.mono)
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: Theme.Size.slotNumber)
                Icon(.today).foregroundStyle(task.topSlot != nil ? Theme.Palette.accent : Theme.Palette.textTertiary)
                Text(task.title).font(Theme.Fonts.body).foregroundStyle(Theme.Palette.text).lineLimit(1)
                Spacer()
                RowMeta(task: task)
            }
            .padding(.horizontal, Theme.Space.s)
            .frame(height: Theme.Size.row)
            .rowFill(hovering: hovering, selected: highlighted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .help(task.topSlot == nil ? "Add to Top 3" : "Remove from Top 3")
    }
}
