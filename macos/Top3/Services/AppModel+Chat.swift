import AppKit
import SwiftUI

/// The AI chat panel. Its settings live in UserDefaults; nothing from it is stored in the task database.
extension AppModel {
    static let chatPanelKey = "showChatPanel"
    static let chatPanelWidthKey = "chatPanelWidth"
    /// Master switch for copying task data, off until you turn it on.
    static let chatShareKey = "chatShareTasks"
    static let chatPreviewSeenKey = "chatSharePreviewSeen"
    static let chatSectionKeys: [(key: String, title: String, path: WritableKeyPath<ChatSnapshot.Sections, Bool>)] = [
        ("chatIncludeTop3", "Top 3", \.top3),
        ("chatIncludeLists", "Open tasks by list", \.lists),
        ("chatIncludeWaiting", "Waiting On", \.waiting),
        ("chatIncludeIdeas", "Parking Lot ideas", \.ideas),
        ("chatIncludeEvents", "Today's calendar events", \.events),
        ("chatIncludeNotes", "Task notes (shortened)", \.notes),
    ]

    /// Cmd-J: show or hide the side panel, or bring the pop-out window forward when the chat is popped out.
    func toggleChatPanel() {
        if ChatSession.shared.poppedOut {
            chatWindow?.makeKeyAndOrderFront(nil)
            return
        }
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: Self.chatPanelKey), forKey: Self.chatPanelKey)
    }

    private var chatWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("chat") == true }
    }

    var chatShareEnabled: Bool { UserDefaults.standard.bool(forKey: Self.chatShareKey) }

    var chatSections: ChatSnapshot.Sections {
        var s = ChatSnapshot.Sections()
        let d = UserDefaults.standard
        for item in Self.chatSectionKeys { s[keyPath: item.path] = d.object(forKey: item.key) as? Bool ?? true }
        return s
    }

    func chatSnapshotText(prompt: ChatPrompt?) -> String {
        ChatSnapshot.build(chatSnapshotInput(), sections: chatSections, prompt: prompt)
    }

    func chatSnapshotInput() -> ChatSnapshot.Input {
        let all = allTasks()
        func item(_ t: TaskItem) -> ChatSnapshot.Item {
            ChatSnapshot.Item(title: t.title, notes: t.notes, dueDate: t.dueDate, hasDueTime: t.hasDueTime, priority: t.priority,
                              estimateMinutes: t.estimateMinutes, isCompleted: t.isCompleted, waitingOn: t.waitingOn,
                              followUpDate: t.followUpDate)
        }
        return ChatSnapshot.Input(
            today: DayKey.date(from: today) ?? Date(),
            top3: pinned(in: all).mapValues(item),
            haveTo: ordered(.haveTo, in: all).map(item),
            niceTo: ordered(.niceTo, in: all).map(item),
            waiting: ordered(.waitingOn, in: all).map(item),
            ideas: ordered(.parkingLot, in: all).map(item),
            events: calendar.todayEvents.map { .init(title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay) })
    }

    /// "Send my tasks" (Cmd-Shift-J, the panel button, a prompt chip). The first time, and whenever sharing
    /// is off, the preview sheet shows exactly what would be copied. Nothing is ever typed into the chat.
    func copyTasksForChat(prompt: ChatPrompt? = nil) {
        let d = UserDefaults.standard
        guard chatShareEnabled, d.bool(forKey: Self.chatPreviewSeenKey) else {
            if !ChatSession.shared.poppedOut { d.set(true, forKey: Self.chatPanelKey) }
            ChatSession.shared.preview = ChatPreviewRequest(prompt: prompt)
            return
        }
        copyToClipboard(chatSnapshotText(prompt: prompt))
    }

    func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        let session = ChatSession.shared
        withAnimation(Theme.Motion.standard) { session.copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Motion.toastDuration) {
            withAnimation(Theme.Motion.standard) { session.copied = false }
        }
    }
}
