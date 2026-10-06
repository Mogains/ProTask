import AppKit
import SwiftUI

/// The AI chat panel. Its settings live in UserDefaults; nothing from it is stored in the task database.
extension AppModel {
    static let chatPanelKey = "showChatPanel"
    static let chatPanelWidthKey = "chatPanelWidth"

    /// Cmd-J: show or hide the side panel, or bring the pop-out window forward when the chat is popped out.
    func toggleChatPanel() {
        if ChatSession.shared.poppedOut {
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("chat") == true }?.makeKeyAndOrderFront(nil)
            return
        }
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: Self.chatPanelKey), forKey: Self.chatPanelKey)
    }
}
