import SwiftUI

struct DoneView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]

    var body: some View {
        let done = DoneView.completed(in: tasks)
        let groups = Dictionary(grouping: done) { DayKey.key(for: $0.completedAt ?? Date(), resetHour: model.resetHour) }
        let days = groups.keys.sorted(by: >)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if done.isEmpty { EmptyLine(text: "Nothing completed yet.").padding(.leading, Theme.Space.s) }
                ForEach(days, id: \.self) { day in
                    let items = groups[day] ?? []
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(title: label(day), detail: "\(items.count)")
                            .padding(.leading, Theme.Space.s)
                            .frame(height: Theme.Size.row)
                        ForEach(items) { TaskRow(task: $0, showDivider: $0.id != items.last?.id, showHandle: false) }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: Theme.Size.contentMaxWidth, alignment: .leading)
        }
    }

    static func completed(in tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { $0.isCompleted && $0.topSlot == nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private func label(_ day: String) -> String {
        if day == model.today { return "Today" }
        if day == DayKey.adding(-1, to: model.today) { return "Yesterday" }
        return DayKey.date(from: day)?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) ?? day
    }
}
