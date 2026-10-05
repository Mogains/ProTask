import Foundation
import UserNotifications

/// One-hour reminders for Parking Lot ideas, with actions that work even when the app is closed.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let category = "PARKING_LOT_IDEA"
    static let reminderInterval: TimeInterval = 3600

    enum Action: String {
        case sendHaveTo = "SEND_HAVE_TO"
        case sendNiceTo = "SEND_NICE_TO"
        case delete = "DELETE"
        case keep = "KEEP"
        /// The notification itself was clicked.
        case open = "OPEN"
    }

    /// Called on the main thread for every Parking Lot notification response.
    var onAction: ((UUID, Action) -> Void)?
    /// Called on the main thread for other notifications (wrap-up, focus, follow-ups): identifier and action id.
    var onOther: ((String, String) -> Void)?

    static let eveningID = "evening-wrapup"
    static let generalCategory = "PROTASK_GENERAL"

    private var center: UNUserNotificationCenter { .current() }

    /// Off for debug runs on a throwaway database, so sample data never schedules real notifications.
    var schedulingEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["TOP3_STORE_PATH"] == nil
        #else
        return true
        #endif
    }()

    /// Removes pending/delivered notifications that no longer belong to anything (e.g. deleted tasks).
    func removeOrphans(keep: (String) -> Bool) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { !keep($0) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { !keep($0) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    /// Must run before the app finishes launching so actions on a closed app are delivered.
    func configure() {
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Action.sendHaveTo.rawValue, title: "Send to Have to do", options: []),
            UNNotificationAction(identifier: Action.sendNiceTo.rawValue, title: "Send to Nice to do", options: []),
            UNNotificationAction(identifier: Action.keep.rawValue, title: "Keep in Parking Lot", options: []),
            UNNotificationAction(identifier: Action.delete.rawValue, title: "Delete", options: [.destructive]),
        ]
        center.setNotificationCategories(Set([
            UNNotificationCategory(identifier: Self.category, actions: actions, intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.generalCategory, actions: [], intentIdentifiers: [], options: []),
        ] + extraCategories))
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func schedule(id: UUID, title: String, at date: Date) {
        guard schedulingEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Parking Lot"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.threadIdentifier = "parking-lot"
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        // Same identifier replaces any earlier reminder for this idea.
        center.add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger))
    }

    /// Categories added by other features (follow-ups).
    var extraCategories: [UNNotificationCategory] = []

    /// A notification at a fixed time every day.
    func scheduleDaily(identifier: String, title: String, body: String, hour: Int, minute: Int) {
        guard schedulingEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.generalCategory
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// A one-off notification at a date (or after a delay).
    func scheduleOnce(identifier: String, title: String, body: String, at date: Date, category: String = generalCategory) {
        guard schedulingEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancel(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancel(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    func pendingIDs() async -> Set<String> {
        Set(await center.pendingNotificationRequests().map(\.identifier))
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        let identifier = response.notification.request.identifier
        guard let id = UUID(uuidString: identifier) else {
            let actionID = response.actionIdentifier
            DispatchQueue.main.async { self.onOther?(identifier, actionID) }
            return
        }
        let action = Action(rawValue: response.actionIdentifier) ?? .open
        DispatchQueue.main.async { self.onAction?(id, action) }
    }
}
