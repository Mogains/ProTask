import SwiftUI

struct PaletteItem: Identifiable {
    enum Kind { case action, section, task, idea }
    let id: String
    let title: String
    var detail: String?
    var shortcut: String?
    let kind: Kind
    let icon: IconName
    let run: () -> Void
}

/// Cmd+K: fuzzy search over actions, sections, tasks and Parking Lot ideas. Keyboard only.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    @State private var query = ""
    @State private var index = 0

    var body: some View {
        let results = filtered
        ZStack(alignment: .top) {
            Theme.Palette.shadow
                .ignoresSafeArea()
                .onTapGesture { model.showPalette = false }
            VStack(spacing: 0) {
                InputField(placeholder: "Search tasks, ideas and actions", text: $query, font: Theme.Fonts.input,
                           leadingIcon: .search, bordered: false, focusOnAppear: true) { run(results) }
                    .padding(Theme.Space.m)
                Hairline()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            if results.isEmpty { EmptyLine(text: "No matches.").padding(.horizontal, Theme.Space.m) }
                            ForEach(Array(results.enumerated()), id: \.element.id) { i, item in
                                PaletteRow(item: item, selected: i == index)
                                    .id(i)
                                    .onTapGesture { index = i; run(results) }
                            }
                        }
                        .padding(Theme.Space.xs)
                    }
                    .frame(maxHeight: Theme.Size.row * CGFloat(Theme.Size.paletteMaxRows))
                    .onChange(of: index) { _, i in proxy.scrollTo(i) }
                }
            }
            .frame(width: Theme.Size.paletteWidth)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
            .padding(.top, Theme.Size.paletteTopOffset)
        }
        .onChange(of: query) { index = 0 }
        .background(KeyMonitor(active: true) { event in
            switch event.keyCode {
            case KeyMonitor.down: index = min(index + 1, max(results.count - 1, 0)); return true
            case KeyMonitor.up: index = max(index - 1, 0); return true
            case KeyMonitor.escape: model.showPalette = false; return true
            default: return false
            }
        })
    }

    private func run(_ results: [PaletteItem]) {
        guard results.indices.contains(index) else { return }
        let item = results[index]
        model.showPalette = false
        DispatchQueue.main.async { item.run() }
    }

    private var filtered: [PaletteItem] {
        let all = model.paletteActions() + taskItems
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Array(all.prefix(Theme.Size.paletteMaxRows * 2))
        }
        return all
            .compactMap { item in Fuzzy.score(query, in: item.title).map { (item, $0 + (item.kind == .action ? 2 : 0)) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var taskItems: [PaletteItem] {
        tasks.filter { !$0.isCompleted }.map { t in
            PaletteItem(id: t.id.uuidString, title: t.title, detail: t.topSlot != nil ? "Top 3" : t.list.title,
                        kind: t.isIdea ? .idea : .task, icon: t.isIdea ? .idea : .today) { model.reveal(t) }
        }
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let selected: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Icon(item.icon).foregroundStyle(selected ? Theme.Palette.text : Theme.Palette.textTertiary)
            Text(item.title).font(Theme.Fonts.body).foregroundStyle(Theme.Palette.text).lineLimit(1)
            Spacer()
            if let detail = item.detail {
                Text(detail).font(Theme.Fonts.secondary).foregroundStyle(Theme.Palette.textTertiary)
            }
            if let shortcut = item.shortcut {
                Text(shortcut).font(Theme.Fonts.secondary).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: Theme.Size.row)
        .rowFill(hovering: false, selected: selected)
        .contentShape(Rectangle())
    }
}
