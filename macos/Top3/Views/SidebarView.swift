import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]

    var body: some View {
        let selection = Binding<SidebarSection?>(get: { model.section }, set: { if let s = $0 { model.section = s } })
        let pinnedOpen = tasks.filter { $0.topSlot != nil && !$0.isCompleted }.count
        List(selection: selection) {
            Section {
                row(.today, "Today", "star", pinnedOpen)
                    .dropDestination(for: TaskRef.self) { items, _ in
                        items.first.map { model.pin($0.id) } != nil
                    }
            }
            Section("Lists") {
                ForEach(ListKind.allCases) { list in
                    let count = model.ordered(list, in: tasks).count
                    if list == .parkingLot {
                        row(.list(list), list.title, list.symbol, count)
                    } else {
                        row(.list(list), list.title, list.symbol, count)
                            .dropDestination(for: TaskRef.self) { items, _ in
                                guard let ref = items.first else { return false }
                                withAnimation(.snappy) { model.move(ref.id, to: list, before: nil, manual: false) }
                                return true
                            }
                    }
                }
            }
            Section {
                row(.calendar, "Calendar", "calendar", 0)
                row(.done, "Done", "checkmark.circle", 0)
            }
        }
        .listStyle(.sidebar)
        .font(Theme.body)
    }

    private func row(_ section: SidebarSection, _ title: String, _ symbol: String, _ count: Int) -> some View {
        Label(title, systemImage: symbol)
            .badge(count)
            .tag(section)
    }
}
