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

// MARK: Paste reply

extension AppModel {
    /// Reads the reply you copied from the chat and shows its protask-actions as a confirm card.
    /// The text is untrusted: see ChatActions. It is never stored or logged.
    func pasteChatReply() {
        let session = ChatSession.shared
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return showChatNotice("Copy the assistant's reply first, then press Paste reply.")
        }
        let parsed = ChatActions.parse(text)
        guard parsed.foundBlock else {
            return showChatNotice("No protask-actions block in the copied text.")
        }
        let refs = allTasks().map {
            ChatActions.TaskRef(id: $0.id, title: $0.title, list: $0.list, isCompleted: $0.isCompleted, topSlot: $0.topSlot)
        }
        withAnimation(Theme.Motion.standard) { session.flow.review(ChatActions.plan(parsed, tasks: refs)) }
    }

    func cancelChatPlan() {
        withAnimation(Theme.Motion.standard) { ChatSession.shared.flow.cancel() }
    }

    func approveChatPlan() {
        let session = ChatSession.shared
        withAnimation(Theme.Motion.standard) {
            _ = session.flow.approve(now: Date()) { applyChatPlan($0) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ChatConfirmFlow.undoWindow) {
            withAnimation(Theme.Motion.standard) { session.flow.expire(now: Date()) }
        }
    }

    func undoChatPlan() {
        guard let undo = ChatSession.shared.flow.takeUndo(now: Date()) else { return }
        restore(undo)
    }

    private func showChatNotice(_ text: String) {
        let session = ChatSession.shared
        withAnimation(Theme.Motion.standard) { session.notice = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Motion.toastDuration) {
            if session.notice == text { withAnimation(Theme.Motion.standard) { session.notice = nil } }
        }
    }

    private func chatFields() -> [UUID: ChatTaskFields] {
        Dictionary(uniqueKeysWithValues: allTasks().map {
            ($0.id, ChatTaskFields(list: $0.list, position: $0.position, topSlot: $0.topSlot, topDay: $0.topDay,
                                   dueDate: $0.dueDate, hasDueTime: $0.hasDueTime, unscheduled: $0.unscheduled))
        })
    }

    /// Applies approved changes through the same paths as the UI, so calendar events and reminders follow.
    private func applyChatPlan(_ plan: ChatActions.Plan) -> ChatUndo {
        let before = chatFields()
        var created: [UUID] = []
        for change in plan.changes {
            switch change {
            case let .add(list, title, due, hasTime):
                if let t = addTask(TaskDraft(title: title, list: list, dueDate: due, hasDueTime: due != nil && hasTime)) {
                    created.append(t.id)
                }
            case let .move(id, _, to):
                move(id, to: to, before: nil, manual: false)
            case let .top3(slot, id, _):
                pin(id, slot: slot)
            case let .due(id, _, date, hasTime):
                guard let t = task(id) else { continue }
                t.dueDate = date
                t.hasDueTime = hasTime
                t.unscheduled = false
                t.modifiedAt = Date()
                calendar.sync(t, today: today)
                save()
            }
        }
        refreshDayLog()
        save()
        return ChatUndo.diff(before: before, after: chatFields(), created: created)
    }

    private func restore(_ undo: ChatUndo) {
        for id in undo.created {
            guard let t = task(id) else { continue }
            calendar.removeEvents(of: t)
            notifications.cancel(id: t.id)
            if selectedTaskID == t.id { selectedTaskID = nil }
            context.delete(t)
        }
        for (id, f) in undo.before {
            guard let t = task(id) else { continue }
            t.list = f.list
            t.position = f.position
            t.topSlot = f.topSlot
            t.topDay = f.topDay
            t.dueDate = f.dueDate
            t.hasDueTime = f.hasDueTime
            t.unscheduled = f.unscheduled
            t.modifiedAt = Date()
            calendar.sync(t, today: today)
        }
        refreshDayLog()
        save()
        showToast("Undone")
    }
}
