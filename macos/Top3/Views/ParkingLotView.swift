import SwiftUI

struct ParkingLotView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    @State private var text = ""

    var body: some View {
        let ideas = model.ordered(.parkingLot, in: tasks)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                InputField(placeholder: "Park an idea and press Return", text: $text, leadingSymbol: "plus",
                           focusOnAppear: true) {
                    if model.addIdea(text) { withAnimation(Theme.Motion.list) { text = "" } }
                }
                VStack(spacing: 0) {
                    if ideas.isEmpty {
                        EmptyLine(text: "No parked ideas.").padding(.leading, Theme.Space.s)
                    }
                    ForEach(ideas) { idea in
                        TaskRow(task: idea, showDivider: idea.id != ideas.last?.id)
                            .draggable(TaskRef(id: idea.id)) { DragPreview(title: idea.title) }
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: Theme.Size.contentMaxWidth, alignment: .leading)
        }
    }
}
