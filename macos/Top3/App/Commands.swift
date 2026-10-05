import SwiftUI

struct Top3Commands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            WindowAction("New Task", key: "n", modifiers: .command) { model.newTask() }
            WindowAction("Quick Add to Parking Lot", key: "p", modifiers: [.command, .shift]) { model.showQuickPark = true }
        }
        CommandMenu("Task") {
            ForEach(Top3Planner.slots, id: \.self) { n in
                Button("Add to Top 3, Slot \(n)") { model.assignSelected(to: n) }
                    .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: .command)
            }
            Divider()
            Button("Edit Task") { model.editSelected() }.keyboardShortcut("e", modifiers: .command)
            Button("Mark as Done or Not Done") { model.toggleSelectedDone() }.keyboardShortcut(.return, modifiers: .command)
            Button("Start or Stop Focus Timer") { model.toggleFocusForSelection() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("Delete Task") { model.deleteSelected() }
        }
        CommandGroup(before: .sidebar) {
            WindowAction("Command Palette", key: "k", modifiers: .command) { model.showPalette.toggle() }
            WindowAction("Toggle Sidebar", key: "s", modifiers: [.command, .control]) {
                withAnimation(Theme.Motion.list) { model.toggleSidebar() }
            }
            Divider()
            Button("Today") { model.section = .today }.keyboardShortcut("0", modifiers: [.command, .option])
            ForEach(Array(ListKind.allCases.enumerated()), id: \.element) { i, l in
                Button(l.title) { model.section = .list(l) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .option])
            }
            Divider()
        }
    }
}

/// A menu button that reopens the main window first if it was closed.
private struct WindowAction: View {
    @Environment(\.openWindow) private var openWindow
    let title: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let action: () -> Void

    init(_ title: String, key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) {
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.action = action
    }

    var body: some View {
        Button(title) {
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { openWindow(id: "main") }
            NSApp.activate()
            DispatchQueue.main.async(execute: action)
        }
        .keyboardShortcut(key, modifiers: modifiers)
    }
}
