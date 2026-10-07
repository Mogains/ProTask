import SwiftData
import SwiftUI

/// What a link picker adds.
enum LinkPickerKind: String, Identifiable {
    case goal, task
    var id: String { rawValue }
}

// MARK: - Section

/// Linked goals (what this goal depends on and what it is needed for) and linked tasks.
/// Routines join here once the Routines section exists.
struct GoalLinksSection: View {
    @Environment(AppModel.self) private var model
    let goal: Goal

    @Query(sort: \Goal.sortOrder) private var goals: [Goal]
    @Query private var dependencies: [GoalDependency]
    @Query(sort: \VisionTimeline.sortOrder) private var timelines: [VisionTimeline]
    @Query private var tasks: [TaskItem]

    init(goal: Goal) {
        self.goal = goal
        let id: UUID? = goal.id
        _tasks = Query(filter: #Predicate<TaskItem> { $0.goalID == id }, sort: \TaskItem.createdAt)
    }

    var body: some View {
        let edges = dependencies.map(\.edge)
        let upstream = GoalLinks.dependsOn(goal.id, edges: edges).compactMap { id in goals.first { $0.id == id } }
        let downstream = GoalLinks.neededFor(goal.id, edges: edges).compactMap { id in goals.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 0) {
            PanelSection(title: "Linked goals", detail: upstream.isEmpty && downstream.isEmpty ? nil : "\(upstream.count + downstream.count)") {
                IconButton(icon: .link, help: "Link a goal…") { model.visionBoard.linkPicker = .goal }
            } content: {
                if upstream.isEmpty && downstream.isEmpty {
                    Text("Link goals that have to come first, or that this one makes possible.")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !upstream.isEmpty { group("Depends on", upstream, relation: .dependsOn) }
                if !downstream.isEmpty { group("Needed for", downstream, relation: .neededFor) }
            }
            Hairline().padding(.horizontal, Theme.Space.l)
            PanelSection(title: "Tasks", detail: tasks.isEmpty ? nil : "\(tasks.filter(\.isCompleted).count) of \(tasks.count) done") {
                IconButton(icon: .link, help: "Link a task…") { model.visionBoard.linkPicker = .task }
            } content: {
                if tasks.isEmpty {
                    Text("Link the everyday tasks that move this goal along.")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(tasks) { task in LinkedTaskRow(task: task) }
                    }
                }
            }
        }
    }

    private func group(_ title: String, _ linked: [Goal], relation: GoalLinkRelation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.bottom, Theme.Space.xxs)
            ForEach(linked) { other in
                LinkedGoalRow(goal: other, color: timelines.first { $0.id == other.timelineID }?.color ?? .fallback) {
                    switch relation {
                    case .dependsOn: model.removeDependency(upstream: other.id, downstream: goal.id)
                    case .neededFor: model.removeDependency(upstream: goal.id, downstream: other.id)
                    }
                }
            }
        }
    }
}

/// A linked goal: click to open it; the close button unlinks it.
private struct LinkedGoalRow: View {
    @Environment(AppModel.self) private var model
    let goal: Goal
    let color: TimelineColor
    let unlink: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button { model.openGoal(goal.id) } label: {
                HStack(spacing: Theme.Space.s) {
                    Circle().fill(Theme.Vision.color(color)).frame(width: Theme.Timeline.laneDot, height: Theme.Timeline.laneDot)
                    Text(goal.title)
                        .font(Theme.Fonts.small)
                        .foregroundStyle(Theme.Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(goal.status.title)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(.horizontal, Theme.Space.xs)
                .frame(minHeight: Theme.Size.row - Theme.Space.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(goal.title)")
            .accessibilityLabel("\(goal.title), \(goal.status.title). Open")
            IconButton(icon: .close, help: "Unlink \(goal.title)", action: unlink)
        }
        .rowFill(hovering: hovering)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
    }
}

/// A linked task: tick it off here, or unlink it (the task itself stays).
private struct LinkedTaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Button { model.setCompleted(task, !task.isCompleted) } label: {
                Checkbox(checked: task.isCompleted)
                    .frame(width: Theme.Size.iconButton, height: Theme.Size.iconButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(task.isIdea)
            .accessibilityLabel(task.isCompleted ? "Mark \(task.title) as not done" : "Mark \(task.title) as done")
            Text(task.title)
                .font(Theme.Fonts.small)
                .foregroundStyle(task.isCompleted ? Theme.Palette.textTertiary : Theme.Palette.text)
                .strikethrough(task.isCompleted, color: Theme.Palette.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(task.list.title)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            IconButton(icon: .close, help: "Unlink \(task.title)") { model.linkTask(task, to: nil) }
        }
        .frame(minHeight: Theme.Size.row - Theme.Space.xs)
        .rowFill(hovering: hovering)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
    }
}

// MARK: - Picker

/// Search and pick a goal (as a dependency either way) or a task to link. Keyboard first: type, arrows, Return.
/// Goals that can't be linked stay listed, dimmed, with the reason (this goal, already linked, would make a loop).
struct GoalLinkPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID
    let kind: LinkPickerKind

    @Query(sort: \Goal.sortOrder) private var goals: [Goal]
    @Query(sort: \VisionTimeline.sortOrder) private var timelines: [VisionTimeline]
    @Query private var dependencies: [GoalDependency]
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]

    @State private var query = ""
    @State private var index = 0
    @State private var relation: GoalLinkRelation = .dependsOn

    /// One row of the list.
    private struct Row: Identifiable {
        let id: UUID
        let title: String
        let detail: String
        let color: TimelineColor?
        let blocked: String?
    }

    var body: some View {
        let rows = self.rows
        VStack(alignment: .leading, spacing: 0) {
            InputField(placeholder: kind == .goal ? "Search goals" : "Search tasks", text: $query, font: Theme.Fonts.input,
                       leadingIcon: .search, bordered: false, focusOnAppear: true, onSubmit: { pick(rows) })
                .padding(Theme.Space.m)
            if kind == .goal {
                HStack(spacing: Theme.Space.s) {
                    Text("This goal").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
                    Segments(options: GoalLinkRelation.allCases, selection: $relation) { $0.title.lowercased() }
                    Text("the one you pick").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.s)
            }
            Hairline()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if rows.isEmpty {
                            EmptyLine(text: emptyText).padding(.horizontal, Theme.Space.s)
                        }
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            PickerRow(title: row.title, detail: row.blocked ?? row.detail, color: row.color,
                                      blocked: row.blocked != nil, selected: i == index)
                                .id(i)
                                .onTapGesture {
                                    index = i
                                    pick(rows)
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction {
                                    index = i
                                    pick(rows)
                                }
                        }
                    }
                    .padding(Theme.Space.xs)
                }
                .frame(height: Theme.GoalPanel.pickerListHeight)
                .onChange(of: index) { _, i in proxy.scrollTo(i) }
            }
            Hairline()
            HStack(spacing: Theme.Space.xs) {
                Text(kind == .goal ? "↑↓ to choose, ↩ to link" : "↑↓ to choose, ↩ to link. A task belongs to one goal at a time.")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.ghost)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Theme.Space.m)
        }
        .frame(width: Theme.Size.sheetWidth)
        .font(Theme.Fonts.body)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .onChange(of: query) { index = 0 }
        .onChange(of: relation) { index = 0 }
        .background(KeyMonitor(active: true) { event in
            switch event.keyCode {
            case KeyMonitor.down: index = min(index + 1, max(rows.count - 1, 0)); return true
            case KeyMonitor.up: index = max(index - 1, 0); return true
            default: return false
            }
        })
    }

    private var emptyText: String {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return "No matches." }
        return kind == .goal ? "There are no other goals yet." : "There are no open tasks to link."
    }

    private var rows: [Row] {
        switch kind {
        case .goal: goalRows
        case .task: taskRows
        }
    }

    private var goalRows: [Row] {
        let edges = dependencies.map(\.edge)
        // Board order: by timeline, then within it.
        let lane = Dictionary(timelines.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = goals.sorted { (lane[$0.timelineID] ?? .max, $0.sortOrder) < (lane[$1.timelineID] ?? .max, $1.sortOrder) }
        let byID = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let candidates = GoalLinks.candidates(for: goalID, relation: relation, among: ordered.map(\.id), edges: edges)
        let rows: [Row] = candidates.compactMap { c in
            guard let g = byID[c.id] else { return nil }
            let timeline = timelines.first { $0.id == g.timelineID }
            return Row(id: g.id, title: g.title, detail: timeline?.name ?? "", color: timeline?.color, blocked: c.check.reason)
        }
        return LinkSearch.filter(rows, query: query) { $0.title }
    }

    private var taskRows: [Row] {
        let titles = Dictionary(goals.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        // Tasks without a goal first, in list order; then the ones linked to another goal.
        let lists = Dictionary(ListKind.allCases.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let open = tasks.filter { !$0.isCompleted && $0.goalID != goalID }
            .enumerated()
            .sorted { a, b in
                let ka = (a.element.goalID == nil ? 0 : 1, lists[a.element.list] ?? 0, a.offset)
                let kb = (b.element.goalID == nil ? 0 : 1, lists[b.element.list] ?? 0, b.offset)
                return ka < kb
            }
            .map(\.element)
        let rows = open.map { t in
            Row(id: t.id, title: t.title,
                detail: t.goalID.flatMap { titles[$0] }.map { "Linked to \($0)" } ?? t.list.title, color: nil, blocked: nil)
        }
        return LinkSearch.filter(rows, query: query) { $0.title }
    }

    private func pick(_ rows: [Row]) {
        guard rows.indices.contains(index) else { return }
        let row = rows[index]
        if let reason = row.blocked {
            model.showToast(reason)
            return
        }
        guard let goal = model.goal(goalID) else { return dismiss() }
        switch kind {
        case .goal:
            guard let other = model.goal(row.id) else { return }
            let ok = relation == .dependsOn ? model.addDependency(upstream: other, downstream: goal)
                : model.addDependency(upstream: goal, downstream: other)
            if ok { dismiss() }
        case .task:
            guard let task = model.allTasks().first(where: { $0.id == row.id }) else { return }
            model.linkTask(task, to: goal)
            dismiss()
        }
    }
}

private struct PickerRow: View {
    let title: String
    let detail: String
    let color: TimelineColor?
    let blocked: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let color {
                Circle().fill(Theme.Vision.color(color))
                    .frame(width: Theme.Timeline.laneDot, height: Theme.Timeline.laneDot)
                    .opacity(blocked ? Theme.Opacity.disabled : 1)
            }
            Text(title)
                .font(Theme.Fonts.body)
                .foregroundStyle(blocked ? Theme.Palette.textTertiary : Theme.Palette.text)
                .lineLimit(1)
            Spacer()
            Text(detail)
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: Theme.Size.row)
        .rowFill(hovering: false, selected: selected)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(blocked ? detail : "Link")
    }
}
