import AppKit
import SwiftUI

/// Window-level toggles and the command palette's actions.
extension AppModel {
    static let sidebarKey = "showSidebar"
    static let panelKey = "showCalendarPanel"
    static let appearanceKey = "appearance"

    func toggleSidebar() {
        let d = UserDefaults.standard
        d.set(!(d.object(forKey: Self.sidebarKey) as? Bool ?? true), forKey: Self.sidebarKey)
    }

    func toggleCalendarPanel() {
        let d = UserDefaults.standard
        d.set(!(d.object(forKey: Self.panelKey) as? Bool ?? true), forKey: Self.panelKey)
    }

    /// "system", "light" or "dark".
    func applyAppearance() {
        switch UserDefaults.standard.string(forKey: Self.appearanceKey) {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func toggleTheme() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        UserDefaults.standard.set(isDark ? "light" : "dark", forKey: Self.appearanceKey)
        applyAppearance()
    }

    /// Shows a task where it lives and selects it.
    func reveal(_ t: TaskItem) {
        section = t.topSlot != nil ? .today : (t.isCompleted ? .done : .list(t.list))
        selectedTaskID = t.id
    }

    func moveSelectedToOtherList() {
        guard let t = task(selectedTaskID) else { return showToast("Select a task first.") }
        let target: ListKind = t.list == .haveTo ? .niceTo : .haveTo
        send(t, to: target)
    }

    func paletteActions() -> [PaletteItem] {
        var items: [PaletteItem] = [
            PaletteItem(id: "new-task", title: "New task", shortcut: "⌘N", kind: .action, icon: .add) { [self] in newTask() },
            PaletteItem(id: "new-idea", title: "New idea", detail: "Parking Lot", shortcut: "⇧⌘P", kind: .action, icon: .quickAdd) { [self] in showQuickPark = true },
            PaletteItem(id: "go-today", title: "Go to Today", shortcut: "⌥⌘0", kind: .section, icon: .today) { [self] in section = .today },
        ]
        for (i, l) in ListKind.allCases.enumerated() {
            items.append(PaletteItem(id: "go-\(l.rawValue)", title: "Go to \(l.title)", shortcut: "⌥⌘\(i + 1)", kind: .section,
                                     icon: l == .parkingLot ? .parking : l == .niceTo ? .niceTo : l == .waitingOn ? .waiting : .haveTo) { [self] in section = .list(l) })
        }
        items += [
            PaletteItem(id: "go-calendar", title: "Go to Calendar", kind: .section, icon: .calendar) { [self] in section = .calendar },
            PaletteItem(id: "go-done", title: "Go to Done", kind: .section, icon: .done) { [self] in section = .done },
            PaletteItem(id: "pin", title: "Add selected task to Top 3", shortcut: "⌘1", kind: .action, icon: .today) { [self] in
                if let t = task(selectedTaskID) { pin(t.id) } else { showToast("Select a task first.") }
            },
            PaletteItem(id: "done", title: "Mark selected task done", shortcut: "⌘↩", kind: .action, icon: .done) { [self] in toggleSelectedDone() },
            PaletteItem(id: "move", title: "Move selected task to the other list", kind: .action, icon: .send) { [self] in moveSelectedToOtherList() },
            PaletteItem(id: "theme", title: "Toggle light and dark theme", kind: .action, icon: .panel) { [self] in toggleTheme() },
            PaletteItem(id: "sidebar", title: "Toggle sidebar", shortcut: "⌃⌘S", kind: .action, icon: .sidebar) { [self] in toggleSidebar() },
            PaletteItem(id: "panel", title: "Toggle calendar panel", kind: .action, icon: .panel) { [self] in toggleCalendarPanel() },
        ]
        items += extraPaletteActions()
        return items
    }
}
