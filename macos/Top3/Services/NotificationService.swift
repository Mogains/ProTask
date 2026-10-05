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

    /// Called on the main thread for every notification response.
    var onAction: ((UUID, Action) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    /// Must run before the app finishes launching so actions on a closed app are delivered.
    func configure() {
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Action.sendHaveTo.rawValue, title: "Send to Have to do", options: []),
            UNNotificationAction(identifier: Action.sendNiceTo.rawValue, title: "Send to Nice to do", options: []),
            UNNotificationAction(identifier: Action.keep.rawValue, title: "Keep in Parking Lot", options: []),
            UNNotificationAction(identifier: Action.delete.rawValue, title: "Delete", options: [.destructive]),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: actions, intentIdentifiers: [], options: []),
        ])
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func schedule(id: UUID, title: String, at date: Date) {
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
        guard let id = UUID(uuidString: response.notification.request.identifier) else { return }
        let action = Action(rawValue: response.actionIdentifier) ?? .open
        DispatchQueue.main.async { self.onAction?(id, action) }
    }
}
