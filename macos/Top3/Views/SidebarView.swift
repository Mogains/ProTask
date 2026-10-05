import SwiftUI

/// Flat, text-only sidebar: 28pt rows, right-aligned counts, subtle fill and a thin left indicator for the selection.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]

    var body: some View {
        let pinnedOpen = tasks.filter { $0.topSlot != nil && !$0.isCompleted }.count
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights; also drags the window.
            WindowDragArea().frame(height: Theme.Size.header)

            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                SidebarRow(section: .today, title: "Today", count: pinnedOpen) { ref in
                    model.pin(ref.id)
                }

                SectionLabel(title: "Lists")
                    .padding(.leading, Theme.Space.s)
                    .padding(.top, Theme.Space.l)
                    .padding(.bottom, Theme.Space.xs)
                ForEach(ListKind.allCases) { list in
                    SidebarRow(section: .list(list), title: list.title,
                               count: model.ordered(list, in: tasks).count,
                               onDrop: list == .parkingLot ? nil : { ref in
                                   withAnimation(Theme.Motion.list) { model.move(ref.id, to: list, before: nil, manual: false) }
                               })
                }

                Spacer().frame(height: Theme.Space.l)
                SidebarRow(section: .calendar, title: "Calendar", count: 0)
                SidebarRow(section: .done, title: "Done", count: 0)
                SidebarRow(section: .review, title: "Review", count: 0)

                SidebarTags(tasks: tasks).padding(.top, Theme.Space.l)
            }
            .padding(.horizontal, Theme.Space.s)

            Spacer()

            FocusTimerView().padding(.horizontal, Theme.Space.s)

            SettingsLink {
                HStack(spacing: Theme.Space.s) {
                    Text("Settings").font(Theme.Fonts.small)
                    Spacer()
                }
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, Theme.Space.s)
                .frame(height: Theme.Size.sidebarRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Space.s)
            .padding(.bottom, Theme.Space.m)
        }
    }
}

struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    let section: SidebarSection
    let title: String
    let count: Int
    var onDrop: ((TaskRef) -> Void)?

    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        let selected = model.section == section
        Button { model.section = section } label: {
            HStack(spacing: Theme.Space.s) {
                Text(title).font(Theme.Fonts.body)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(selected ? Theme.Palette.text : Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Space.s)
            .frame(height: Theme.Size.sidebarRow)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill(selected || targeted ? Theme.Palette.selected : hovering ? Theme.Palette.hover : .clear))
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Size.hairline)
                        .fill(Theme.Palette.accent)
                        .frame(width: Theme.Size.indicator, height: Theme.Size.icon)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .modifier(OptionalDrop(onDrop: onDrop, targeted: $targeted))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct OptionalDrop: ViewModifier {
    let onDrop: ((TaskRef) -> Void)?
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        if let onDrop {
            content.dropDestination(for: TaskRef.self) { items, _ in
                guard let ref = items.first else { return false }
                onDrop(ref)
                return true
            } isTargeted: { on in withAnimation(Theme.Motion.hover) { targeted = on } }
        } else {
            content
        }
    }
}
