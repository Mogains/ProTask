import SwiftUI
import UserNotifications

/// Waiting On: things handed off, with a follow-up date that notifies and surfaces in Today.
extension AppModel {
    static let followUpPrefix = "followup-"
    static let followUpHour = 9
    static let followUpCategory = UNNotificationCategory(identifier: "PROTASK_FOLLOW_UP", actions: [
        UNNotificationAction(identifier: "RECEIVED", title: "Mark received", options: []),
        UNNotificationAction(identifier: "SNOOZE", title: "Snooze 1 day", options: []),
        UNNotificationAction(identifier: "MOVE", title: "Move to Have to do", options: []),
    ], intentIdentifiers: [], options: [])

    static func followUpID(_ id: UUID) -> String { followUpPrefix + id.uuidString }

    /// (Re)schedules the follow-up notification for 9 AM on the follow-up date, or cancels it.
    func scheduleFollowUp(_ t: TaskItem) {
        let identifier = Self.followUpID(t.id)
        notifications.cancel(identifier: identifier)
        guard t.isWaiting, !t.isCompleted, let date = t.followUpDate else { return }
        let at = Calendar.current.date(bySettingHour: Self.followUpHour, minute: 0, second: 0, of: date) ?? date
        guard at > Date() else { return }
        let who = t.waitingOn.isEmpty ? "" : " from \(t.waitingOn)"
        notifications.scheduleOnce(identifier: identifier, title: "Follow up", body: "\(t.title)\(who)", at: at,
                                   category: Self.followUpCategory.identifier)
    }

    func isFollowUpDue(_ t: TaskItem) -> Bool {
        guard t.isWaiting, !t.isCompleted, let d = t.followUpDate else { return false }
        return DayKey.dateKey(d) <= today
    }

    func receive(_ t: TaskItem) {
        setCompleted(t, true)
        showToast("Received: \(t.title).")
    }

    func snoozeFollowUp(_ t: TaskItem) {
        let todayStart = DayKey.date(from: today) ?? Calendar.current.startOfDay(for: Date())
        let base = max(t.followUpDate.map { Calendar.current.startOfDay(for: $0) } ?? todayStart, todayStart)
        t.followUpDate = Calendar.current.date(byAdding: .day, value: 1, to: base)
        scheduleFollowUp(t)
        save()
        showToast("Follow up \(t.followUpDate?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? "tomorrow").")
    }

    func handleFollowUpAction(_ identifier: String, action: String) {
        guard let t = task(UUID(uuidString: String(identifier.dropFirst(Self.followUpPrefix.count)))) else { return }
        switch action {
        case "RECEIVED": receive(t)
        case "SNOOZE": snoozeFollowUp(t)
        case "MOVE": send(t, to: .haveTo)
        default: reveal(t)
        }
    }
}
