import SwiftUI

struct DoneView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]

    var body: some View {
        let done = tasks.filter { $0.isCompleted && $0.topSlot == nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let groups = Dictionary(grouping: done) { DayKey.key(for: $0.completedAt ?? Date(), resetHour: model.resetHour) }
        let days = groups.keys.sorted(by: >)

        if done.isEmpty {
            ContentUnavailableView("Nothing done yet", systemImage: "checkmark.circle",
                                   description: Text("Completed tasks collect here."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Done").font(Theme.title)
                    ForEach(days, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 1) {
                            SectionHeader(title: label(day), detail: "\(groups[day]?.count ?? 0)").padding(.horizontal, 8).padding(.bottom, 3)
                            ForEach(groups[day] ?? []) { TaskRow(task: $0) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
    }

    private func label(_ day: String) -> String {
        if day == model.today { return "Today" }
        if day == DayKey.adding(-1, to: model.today) { return "Yesterday" }
        return DayKey.date(from: day)?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) ?? day
    }
}
