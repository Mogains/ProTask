import SwiftData
import SwiftUI

// MARK: - Notes

/// Markdown notes: shown rendered, edited as plain text. Saved when you press Done, leave the editor, or close the panel.
struct GoalNotesSection: View {
    @Environment(AppModel.self) private var model
    let goal: Goal

    @State private var editing = false
    @State private var text = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        PanelSection(title: "Notes") {
            if editing {
                Button("Done") { finish() }.buttonStyle(.ghost)
            } else if !goal.notes.isEmpty {
                Button("Edit") { begin() }.buttonStyle(.ghost)
            }
        } content: {
            if editing {
                TextEditor(text: $text)
                    .font(Theme.Fonts.small)
                    .foregroundStyle(Theme.Palette.text)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .frame(minHeight: Theme.GoalPanel.notesMinHeight, maxHeight: Theme.GoalPanel.notesMaxHeight)
                    .padding(Theme.Space.xs)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.background))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .strokeBorder(editorFocused ? Theme.Palette.textTertiary : Theme.Palette.border, lineWidth: Theme.Size.hairline))
                    .accessibilityLabel("Notes, in Markdown")
                    .onChange(of: editorFocused) { if !editorFocused { finish() } }
                Text("Markdown works: **bold**, *italic*, - lists, - [ ] checklists, ## headings")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else if goal.notes.isEmpty {
                Button { begin() } label: {
                    Text("Add notes: the why, the plan, what done looks like.")
                        .font(Theme.Fonts.small)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.row, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add notes")
            } else {
                MarkdownNotesView(source: goal.notes)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { begin() }
                    .help("Double-click to edit")
            }
        }
        .onDisappear { if editing { save() } }
    }

    private func begin() {
        text = goal.notes
        editing = true
        DispatchQueue.main.async { editorFocused = true }
    }

    private func finish() {
        guard editing else { return }
        save()
        editing = false
    }

    private func save() {
        guard text != goal.notes else { return }
        let notes = text
        model.editGoal(goal.id) { $0.notes = notes }
    }
}

/// Goal notes rendered block by block (NotesMarkdown), with inline styling from AttributedString(markdown:).
struct MarkdownNotesView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Array(NotesMarkdown.blocks(source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: NoteBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(level == 1 ? Theme.Fonts.heading1 : level == 2 ? Theme.Fonts.heading2 : Theme.Fonts.heading3)
                .foregroundStyle(Theme.Palette.text)
                .padding(.top, Theme.Space.xxs)
        case let .bullet(text, indent):
            listRow(marker: Text("\u{2022}"), text: text, indent: indent)
        case let .numbered(number, text, indent):
            listRow(marker: Text("\(number).").monospacedDigit(), text: text, indent: indent)
        case let .task(done, text, indent):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Checkbox(checked: done)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - Theme.Space.xxs }
                    .accessibilityLabel(done ? "Done" : "Not done")
                Text(inline(text))
                    .foregroundStyle(done ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                    .strikethrough(done, color: Theme.Palette.textTertiary)
            }
            .font(Theme.Fonts.small)
            .padding(.leading, CGFloat(indent) * Theme.GoalPanel.listIndent)
        case let .quote(text):
            HStack(spacing: Theme.Space.s) {
                Rectangle().fill(Theme.Palette.border).frame(width: Theme.GoalPanel.quoteBar)
                Text(inline(text)).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case let .code(text):
            Text(text)
                .font(Theme.Fonts.code)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(Theme.Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.hover))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
        case .rule:
            Hairline().padding(.vertical, Theme.Space.xs)
        case let .paragraph(text):
            Text(inline(text))
                .font(Theme.Fonts.small)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func listRow(marker: Text, text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            marker.foregroundStyle(Theme.Palette.textTertiary)
            Text(inline(text)).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.Fonts.small)
        .padding(.leading, CGFloat(indent) * Theme.GoalPanel.listIndent)
    }

    /// Inline Markdown. Inter has no italic face here, so emphasis also gets the primary text color to stand out.
    private func inline(_ text: String) -> AttributedString {
        guard var s = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(text)
        }
        for run in s.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.emphasized) || intent.contains(.stronglyEmphasized) {
                s[run.range].foregroundColor = Theme.Palette.text
            }
        }
        return s
    }
}

// MARK: - Update log

/// Dated updates on the goal, newest first. Each can carry the metric's value that day, which feeds the graph.
struct GoalLogSection: View {
    @Environment(AppModel.self) private var model
    let goal: Goal
    let color: TimelineColor

    @Query private var logs: [GoalLog]
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var text = ""
    @State private var value = ""

    init(goal: Goal, color: TimelineColor) {
        self.goal = goal
        self.color = color
        let id = goal.id
        _logs = Query(filter: #Predicate<GoalLog> { $0.goalID == id })
    }

    private var parsedValue: Double? { MetricInput.number(value) }
    private var valueIsBad: Bool { !value.trimmingCharacters(in: .whitespaces).isEmpty && parsedValue == nil }
    private var canAdd: Bool { GoalLogOrder.isValid(text: text, metricValue: parsedValue) && !valueIsBad }

    var body: some View {
        let entries = GoalLogOrder.newestFirst(logs.map(\.entry))
        PanelSection(title: "Updates", detail: entries.isEmpty ? nil : "\(entries.count)") {
            composer
            if entries.isEmpty {
                Text("Note what changed, with a date. Values you log here draw the metric graph.")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                        GoalLogRow(entry: entry, unit: goal.metricUnit, color: color, isLast: i == entries.count - 1) {
                            if let log = logs.first(where: { $0.id == entry.id }) { model.deleteGoalLog(log) }
                        }
                    }
                }
                .padding(.top, Theme.Space.xs)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TextField("", text: $text, prompt: Text("What happened?").foregroundStyle(Theme.Palette.textTertiary), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.small)
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(1...5)
                .focusEffectDisabled()
                .onSubmit(add)
                .accessibilityLabel("Update")
            HStack(spacing: Theme.Space.s) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .font(Theme.Fonts.small)
                    .accessibilityLabel("Update date")
                if goal.metric != nil || !goal.metricName.isEmpty {
                    TextField("", text: $value, prompt: Text(goal.metricUnit.isEmpty ? "Value" : goal.metricUnit).foregroundStyle(Theme.Palette.textTertiary))
                        .textFieldStyle(.plain)
                        .font(Theme.Fonts.small)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focusEffectDisabled()
                        .onSubmit(add)
                        .padding(.horizontal, Theme.Space.s)
                        .frame(width: Theme.GoalPanel.logValueField, height: Theme.Size.iconButton)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                            .strokeBorder(valueIsBad ? Theme.Vision.overdue : Theme.Palette.border, lineWidth: Theme.Size.hairline))
                        .help(goal.metricName.isEmpty ? "The metric's value that day (optional)" : "\(goal.metricName) that day (optional)")
                        .accessibilityLabel(goal.metricName.isEmpty ? "Metric value" : goal.metricName)
                }
                Spacer(minLength: 0)
                Button("Add") { add() }
                    .buttonStyle(.ghost)
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : Theme.Opacity.disabled)
                    .accessibilityLabel("Add update")
            }
        }
        .padding(Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.background))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
    }

    private func add() {
        guard canAdd else { return }
        guard model.addGoalLog(to: goal, text: text, date: date, metricValue: parsedValue) != nil else { return }
        text = ""
        value = ""
        date = Calendar.current.startOfDay(for: Date())
    }
}

/// One update: a dot on the rail, the date and value, then the text. Delete shows on hover (and is always reachable
/// by keyboard and VoiceOver).
private struct GoalLogRow: View {
    let entry: GoalLogEntry
    let unit: String
    let color: TimelineColor
    let isLast: Bool
    let delete: () -> Void

    @State private var hovering = false
    @FocusState private var deleteFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            VStack(spacing: Theme.Space.xs) {
                Circle()
                    .fill(Theme.Vision.color(color))
                    .frame(width: Theme.GoalPanel.logDot, height: Theme.GoalPanel.logDot)
                    .padding(.top, Theme.Space.xs + Theme.Space.xxs)
                Rectangle()
                    .fill(isLast ? .clear : Theme.Palette.border)
                    .frame(width: Theme.Size.hairline)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: Theme.GoalPanel.logRailWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.s) {
                    Text(VisionFormat.day(entry.date))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    if let v = entry.metricValue {
                        Text(MetricInput.format(v, unit: unit))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Palette.text)
                            .monospacedDigit()
                            .padding(.horizontal, Theme.Space.xs)
                            .padding(.vertical, Theme.Size.hairline)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Vision.fill(color)))
                    }
                    Spacer(minLength: 0)
                    IconButton(icon: .delete, help: "Delete this update", action: delete)
                        .focused($deleteFocused)
                        .opacity(hovering || deleteFocused ? 1 : 0)
                }
                .frame(minHeight: Theme.Size.iconButton)
                if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(Theme.Fonts.small)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.bottom, isLast ? 0 : Theme.Space.m)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Delete", delete)
    }
}
