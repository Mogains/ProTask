import SwiftData
import SwiftUI

// MARK: - Timeline picker

/// Picks a timeline: its color dot and name, opening a menu of the others.
struct TimelineMenuPicker: View {
    let timelines: [VisionTimeline]
    @Binding var selection: UUID?
    /// Shown when there is nothing to pick from.
    var placeholder = "None"

    var body: some View {
        let current = timelines.first { $0.id == selection }
        PopUpMenuButton(help: "Choose a timeline", padded: false) {
            timelines.map { t in
                .item(t.archived ? "\(t.name) (archived)" : t.name, checked: t.id == selection) { selection = t.id }
            }
        } label: {
            HStack(spacing: Theme.Space.s) {
                if let current {
                    Circle().fill(Theme.Vision.color(current.color))
                        .frame(width: Theme.Timeline.laneDot, height: Theme.Timeline.laneDot)
                }
                Text(current?.name ?? placeholder).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.text)
                Icon(.chevronDown, size: Theme.Size.dragHandle).foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(minHeight: Theme.Size.iconButton)
        }
        .accessibilityLabel("Timeline: \(current?.name ?? placeholder)")
    }
}

// MARK: - Quick add

/// Shift-Cmd-V from anywhere in ProTask: title, timeline, type and target date.
struct GoalQuickAddSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<VisionTimeline> { !$0.archived }, sort: \VisionTimeline.sortOrder) private var timelines: [VisionTimeline]

    @State private var title = ""
    @State private var timelineID: UUID?
    @State private var type: GoalType = .goal
    @State private var hasTarget = false
    @State private var target = Calendar.current.date(byAdding: .month, value: 3, to: Calendar.current.startOfDay(for: Date())) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InputField(placeholder: "New goal", text: $title, font: Theme.Fonts.input, bordered: false, focusOnAppear: true, onSubmit: save)
                .padding(Theme.Space.l)
            Hairline()
            VStack(spacing: 0) {
                PropertyRow(label: "Timeline") {
                    if timelines.isEmpty {
                        Text("Personal (new)").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textSecondary)
                    } else {
                        TimelineMenuPicker(timelines: timelines, selection: $timelineID)
                    }
                }
                PropertyRow(label: "Type") {
                    Segments(options: GoalType.allCases, selection: $type) { $0.title }
                }
                PropertyRow(label: type == .milestone ? "Date" : "Target") {
                    if hasTarget {
                        DatePicker("Target date", selection: $target, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .font(Theme.Fonts.small)
                        Spacer()
                        Button("Clear") { hasTarget = false }.buttonStyle(.ghost)
                    } else {
                        Button("Set date") { hasTarget = true }.buttonStyle(.ghost)
                    }
                }
            }
            .padding(.vertical, Theme.Space.s)
            Hairline()
            HStack(spacing: Theme.Space.xs) {
                Text("Goals stay on this Mac.")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.ghost)
                    .keyboardShortcut(.cancelAction)
                Button("Add goal") { save() }
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
        .onAppear {
            // The selected goal's timeline when there is one, otherwise the first.
            let selected = model.goal(model.selectedGoalID)?.timelineID
            timelineID = timelines.first { $0.id == selected }?.id ?? timelines.first?.id
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let timeline = model.visionTimeline(timelineID) ?? model.ensureTimelineForQuickAdd() else { return }
        let day = Calendar.current.startOfDay(for: target)
        let draft = GoalDraft(title: title, timelineID: timeline.id, type: type, status: .planned,
                              startDate: nil, targetDate: hasTarget ? day : nil)
        guard let goal = model.createGoal(draft) else { return }
        dismiss()
        if model.section == .vision {
            model.selectGoal(goal.id)
            if let span = TimelineDates.span(type: goal.type, start: goal.startDate, target: goal.targetDate, createdAt: goal.createdAt,
                                             calendar: .current) {
                model.visionBoard.reveal(span)
            }
        } else {
            model.showToast("Added to \(timeline.name)")
        }
    }
}

// MARK: - Confirmations

/// Delete a goal, or a timeline. A timeline with goals asks where to move them first; its goals are only deleted
/// with it when you pick that explicitly.
struct VisionPromptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: VisionPrompt

    @State private var destinationID: UUID?
    @State private var confirmDeleteAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch prompt {
            case let .deleteGoal(id): goalBody(model.goal(id))
            case let .deleteTimeline(id): timelineBody(model.visionTimeline(id))
            }
        }
        .frame(width: Theme.Size.sheetWidth)
        .font(Theme.Fonts.body)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
    }

    // MARK: Goal

    @ViewBuilder
    private func goalBody(_ goal: Goal?) -> some View {
        if let goal {
            let logs = model.goalLogs(for: goal.id).count
            let images = model.goalImages(for: goal.id).count
            message(title: "Delete \u{201C}\(goal.title)\u{201D}?",
                    detail: goalDetail(logs: logs, images: images, tasks: model.linkedTasks(of: goal.id).count))
            Hairline()
            HStack(spacing: Theme.Space.xs) {
                Spacer()
                Button("Cancel") { close() }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button("Delete") {
                    model.deleteGoalFromBoard(goal)
                    close()
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Space.m)
        } else {
            missing
        }
    }

    private func goalDetail(logs: Int, images: Int, tasks: Int) -> String {
        var parts: [String] = []
        if logs > 0 { parts.append(logs == 1 ? "1 log entry" : "\(logs) log entries") }
        if images > 0 { parts.append(images == 1 ? "1 picture" : "\(images) pictures") }
        let removed = parts.isEmpty ? "This can't be undone." : "Its \(parts.joined(separator: " and ")) go with it. This can't be undone."
        guard tasks > 0 else { return removed }
        return removed + (tasks == 1 ? " The linked task stays, unlinked." : " The \(tasks) linked tasks stay, unlinked.")
    }

    // MARK: Timeline

    @ViewBuilder
    private func timelineBody(_ timeline: VisionTimeline?) -> some View {
        if let timeline {
            let goals = model.goals(in: timeline.id)
            let others = model.visionTimelines(includeArchived: true).filter { $0.id != timeline.id }
            let n = goals.count
            if n == 0 {
                message(title: "Delete \u{201C}\(timeline.name)\u{201D}?", detail: "This timeline has no goals.")
                Hairline()
                HStack(spacing: Theme.Space.xs) {
                    Spacer()
                    Button("Cancel") { close() }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                    Button("Delete") { deleteTimeline(timeline, movingTo: nil) }
                        .buttonStyle(.primary)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(Theme.Space.m)
            } else {
                let count = n == 1 ? "1 goal" : "\(n) goals"
                message(title: "Delete \u{201C}\(timeline.name)\u{201D}?",
                        detail: others.isEmpty
                            ? "It has \(count), and there is no other timeline to move them to. Archive it to keep them, or delete it with its goals."
                            : "It has \(count). Move them to another timeline first, so nothing is lost.")
                if !others.isEmpty {
                    PropertyRow(label: "Move to") {
                        TimelineMenuPicker(timelines: others, selection: $destinationID)
                    }
                    .padding(.bottom, Theme.Space.s)
                }
                Hairline()
                HStack(spacing: Theme.Space.xs) {
                    // Two steps, so the goals are never deleted by a stray click.
                    Button(confirmDeleteAll ? (n == 1 ? "Click again to delete the goal" : "Click again to delete \(n) goals")
                           : (n == 1 ? "Delete with its goal" : "Delete with its \(n) goals")) {
                        if confirmDeleteAll { deleteTimeline(timeline, movingTo: nil) } else { confirmDeleteAll = true }
                    }
                    .buttonStyle(.ghost)
                    .help("Deletes the goals too, with their logs and pictures")
                    Spacer()
                    Button("Cancel") { close() }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                    if others.isEmpty {
                        Button("Archive instead") {
                            model.setArchived(timeline, true)
                            close()
                        }
                        .buttonStyle(.primary)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Move and delete") {
                            deleteTimeline(timeline, movingTo: model.visionTimeline(destinationID ?? others.first?.id))
                        }
                        .buttonStyle(.primary)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(Theme.Space.m)
                .onAppear { destinationID = destinationID ?? others.first(where: { !$0.archived })?.id ?? others.first?.id }
            }
        } else {
            missing
        }
    }

    private func deleteTimeline(_ timeline: VisionTimeline, movingTo destination: VisionTimeline?) {
        let removed = Set(model.goals(in: timeline.id).map(\.id))
        if let destination {
            model.deleteTimeline(timeline, movingGoalsTo: destination)
        } else {
            if let open = model.visionBoard.openGoalID, removed.contains(open) { model.visionBoard.openGoalID = nil }
            if let selected = model.selectedGoalID, removed.contains(selected) { model.selectedGoalID = nil }
            model.deleteTimeline(timeline)
        }
        close()
    }

    // MARK: Parts

    private func message(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(Theme.font(Theme.TextSize.input, .medium)).foregroundStyle(Theme.Palette.text)
            Text(detail)
                .font(Theme.Fonts.small)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: 0) {
            message(title: "Already deleted", detail: "There is nothing left to delete.")
            Hairline()
            HStack {
                Spacer()
                Button("Close") { close() }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Space.m)
        }
    }

    private func close() {
        dismiss()
        model.visionBoard.prompt = nil
        model.visionBoard.requestFocus()
    }
}
