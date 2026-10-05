import SwiftUI

struct ParkingLotView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let ideas = model.ordered(.parkingLot, in: tasks)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parking Lot").font(Theme.title)
                    Text("Park an idea now, decide later. Each one reminds you after an hour.")
                        .font(Theme.secondary).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: "plus").foregroundStyle(.secondary).imageScale(.small)
                    TextField("Type an idea and press Return", text: $text)
                        .textFieldStyle(.plain)
                        .font(Theme.body)
                        .focused($focused)
                        .onSubmit {
                            if model.addIdea(text) { withAnimation(.snappy) { text = "" } }
                            focused = true
                        }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.rowHover))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Color.accentColor.opacity(0.6) : Theme.hairline))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider().opacity(0.6)

            if ideas.isEmpty {
                ContentUnavailableView("No parked ideas", systemImage: "lightbulb",
                                       description: Text("Ideas you park show up here. Press Shift-Command-P from anywhere in the app to add one."))
                    .font(Theme.body)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(ideas) { idea in
                            IdeaRow(idea: idea)
                                .draggable(TaskRef(id: idea.id)) { DragPreview(title: idea.title) }
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .onAppear { focused = true }
    }
}

struct IdeaRow: View {
    @Environment(AppModel.self) private var model
    let idea: TaskItem

    var body: some View {
        HStack(spacing: 6) {
            TaskRow(task: idea)
            HStack(spacing: 2) {
                action("checklist", "Send to Have to do") { model.send(idea, to: .haveTo) }
                action("tray", "Send to Nice to do") { model.send(idea, to: .niceTo) }
                action("clock.arrow.circlepath", "Keep in Parking Lot and remind me in an hour") { model.snooze(idea) }
                action("trash", "Delete") { model.delete(idea) }
            }
        }
    }

    private func action(_ symbol: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { run() } } label: {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 22, height: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
