import SwiftUI

struct ListScreen: View {
    @Environment(AppModel.self) private var model
    let list: ListKind
    let tasks: [TaskItem]

    var body: some View {
        let items = model.ordered(list, in: tasks)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.title).font(Theme.title)
                        Text(items.count == 1 ? "1 open task" : "\(items.count) open tasks")
                            .font(Theme.secondary).foregroundStyle(.secondary)
                    }
                    Spacer()
                    AutoSortButton(list: list)
                }
                TaskColumn(list: list, tasks: items, showHeader: false)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}
