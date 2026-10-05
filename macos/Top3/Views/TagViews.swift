import SwiftUI

struct TagEditRequest: Identifiable {
    let id = UUID()
    let taskID: UUID
}

/// Collapsible sidebar section: every tag on open tasks, with counts. Click to filter the current view.
struct SidebarTags: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    @AppStorage("tagsExpanded") private var expanded = true

    var body: some View {
        let counts = Self.counts(tasks)
        if !counts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Button { withAnimation(Theme.Motion.standard) { expanded.toggle() } } label: {
                    HStack {
                        SectionLabel(title: "Tags")
                        Spacer()
                        Text(expanded ? "Hide" : "Show").font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .padding(.leading, Theme.Space.s)
                    .padding(.trailing, Theme.Space.s)
                    .frame(height: Theme.Size.sidebarRow)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    ForEach(counts, id: \.tag) { item in
                        TagRow(tag: item.tag, count: item.count)
                    }
                }
            }
        }
    }

    static func counts(_ tasks: [TaskItem]) -> [(tag: String, count: Int)] {
        var c: [String: Int] = [:]
        for t in tasks where !t.isCompleted { for tag in t.tags { c[tag, default: 0] += 1 } }
        return c.map { ($0.key, $0.value) }.sorted { $0.tag < $1.tag }
    }
}

private struct TagRow: View {
    @Environment(AppModel.self) private var model
    let tag: String
    let count: Int
    @State private var hovering = false

    var body: some View {
        let on = model.tagFilter == tag
        Button { withAnimation(Theme.Motion.standard) { model.tagFilter = on ? nil : tag } } label: {
            HStack {
                Text("#\(tag)").font(Theme.Fonts.small)
                Spacer()
                Text("\(count)").font(Theme.Fonts.secondary).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
            }
            .foregroundStyle(on ? Theme.Palette.text : Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Space.s)
            .frame(height: Theme.Size.sidebarRow)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(on ? Theme.Palette.selected : hovering ? Theme.Palette.hover : .clear))
            .overlay(alignment: .leading) {
                if on {
                    RoundedRectangle(cornerRadius: Theme.Size.hairline).fill(Theme.Palette.accent)
                        .frame(width: Theme.Size.indicator, height: Theme.Size.icon)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .help(on ? "Clear the filter" : "Show only #\(tag)")
    }
}

/// Edit a task's tags from its row menu.
struct TagEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: TagEditRequest
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InputField(placeholder: "Tags, separated by spaces", text: $text, font: Theme.Fonts.input, bordered: false,
                       focusOnAppear: true, onSubmit: save)
                .padding(Theme.Space.l)
            Hairline()
            HStack {
                Text(model.task(request.taskID)?.title ?? "").font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(.primary)
            }
            .padding(Theme.Space.m)
        }
        .frame(width: Theme.Size.quickAddWidth)
        .onAppear { text = model.task(request.taskID)?.tags.map { "#\($0)" }.joined(separator: " ") ?? "" }
    }

    private func save() {
        if let t = model.task(request.taskID) {
            t.tags = text.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            model.save()
        }
        dismiss()
    }
}
