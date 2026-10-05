import SwiftUI

/// Evening wrap-up: what got done, what rolls over, a brain dump into the Parking Lot, and Close the day.
struct WrapUpView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    @State private var text = ""
    @State private var parked: [String] = []

    var body: some View {
        let finished = tasks.filter { !$0.isIdea && $0.isCompleted && $0.completedAt.map { DayKey.key(for: $0, resetHour: model.resetHour) == model.today } == true }
        let rolling = tasks.filter { t in
            !t.isIdea && !t.isCompleted && (t.topSlot != nil || (t.dueDate.map { DayKey.dateKey($0) <= model.today } ?? false))
        }
        ZStack {
            Theme.Palette.shadow.ignoresSafeArea().onTapGesture { model.showWrapUp = false }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Space.s) {
                    Text("Wrap up").font(Theme.Fonts.bodyMedium)
                    Text((DayKey.date(from: model.today) ?? Date()).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.l)
                .frame(height: Theme.Size.header)
                Hairline()

                ScrollView { sections(finished: finished, rolling: rolling) }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: Theme.Size.wrapUpMaxHeight)
                    .fixedSize(horizontal: false, vertical: true)
                

                Hairline()
                HStack {
                    Spacer()
                    Button("Not yet") { model.showWrapUp = false }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                    Button("Close the day") { model.closeDay() }.buttonStyle(.primary)
                }
                .padding(Theme.Space.m)
            }
            .frame(width: Theme.Size.paletteWidth)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
        }
        .background(KeyMonitor(active: true) { event in
            if event.keyCode == KeyMonitor.escape { model.showWrapUp = false; return true }
            return false
        })
    }

    private func sections(finished: [TaskItem], rolling: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            list("Finished today", finished, empty: "Nothing checked off today.")
            list("Rolling over", rolling, empty: "Nothing left over.")
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionLabel(title: "Still on your mind")
                InputField(placeholder: "Type a thought and press Return. It goes to the Parking Lot.", text: $text,
               leadingIcon: .quickAdd, focusOnAppear: true) {
                    let t = text.trimmingCharacters(in: .whitespaces)
                    if model.addIdea(t) { parked.append(t); text = "" }
                }
                ForEach(parked, id: \.self) { p in
                    Text(p).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .padding(Theme.Space.l)
    }

    private func list(_ title: String, _ items: [TaskItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(title: title, detail: items.isEmpty ? nil : "\(items.count)")
            if items.isEmpty {
                Text(empty).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
            }
            ForEach(items) { t in
                HStack(spacing: Theme.Space.s) {
                    Checkbox(checked: t.isCompleted)
                    Text(t.title).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.text).lineLimit(1)
                    Spacer()
                    if t.topSlot != nil { Text("Top 3").font(Theme.Fonts.secondary).foregroundStyle(Theme.Palette.textTertiary) }
                }
            }
        }
    }
}
