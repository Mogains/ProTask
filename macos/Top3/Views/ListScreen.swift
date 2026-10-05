import SwiftUI

struct ListScreen: View {
    @Environment(AppModel.self) private var model
    let list: ListKind
    let tasks: [TaskItem]

    var body: some View {
        ScrollView {
            TaskColumn(list: list, tasks: model.ordered(list, in: tasks), showHeader: false)
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.l)
                .frame(maxWidth: Theme.Size.contentMaxWidth, alignment: .leading)
        }
    }
}
