import AppKit
import SwiftUI

/// Evening wrap-up and notification routing for the daily rhythm features.
extension AppModel {
    static let eveningEnabledKey = "eveningWrapUp"
    static let eveningHourKey = "eveningHour"
    static let eveningMinuteKey = "eveningMinute"

    /// Schedules (or cancels) the daily wrap-up reminder from Settings. Default 6:00 PM, on.
    func scheduleEveningWrapUp() {
        let d = UserDefaults.standard
        notifications.cancel(identifier: NotificationService.eveningID)
        guard d.object(forKey: Self.eveningEnabledKey) as? Bool ?? true else { return }
        let hour = d.object(forKey: Self.eveningHourKey) as? Int ?? 18
        let minute = d.object(forKey: Self.eveningMinuteKey) as? Int ?? 0
        notifications.scheduleDaily(identifier: NotificationService.eveningID, title: "Wrap up your day",
                                    body: "See what you finished and park anything still on your mind.", hour: hour, minute: minute)
    }

    func handleNotification(_ identifier: String, action: String) {
        bringMainWindowForward()
        if identifier == NotificationService.eveningID {
            showWrapUp = true
        } else {
            handleOtherNotification(identifier, action: action)
        }
    }

    /// Routes notifications added by later features (focus timer, follow-ups).
    func handleOtherNotification(_ identifier: String, action: String) {
        if identifier == RunningFocus.notificationID { finishFocusIfDue() }
        if identifier.hasPrefix(Self.followUpPrefix) { handleFollowUpAction(identifier, action: action) }
    }

    func bringMainWindowForward() {
        NSApp.activate()
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true || $0.canBecomeMain }) {
            w.makeKeyAndOrderFront(nil)
        }
    }

    /// Unfinished picks leave today's Top 3 now and are offered again in tomorrow's planning.
    func closeDay() {
        let all = allTasks()
        let pins = all.filter { $0.topSlot != nil && $0.topDay == today }
            .map { Rollover.Pin(id: $0.id, topDay: $0.topDay, isCompleted: $0.isCompleted) }
        let result = Rollover.closeDay(pins: pins)
        for t in all where result.unpin.contains(t.id) {
            t.topSlot = nil
            t.topDay = nil
            calendar.sync(t, today: today)
        }
        addRolledOver(result.rolledOver, to: DayKey.adding(1, to: today))
        dayLog(today).dayClosed = true
        refreshDayLog()
        save()
        withAnimation(Theme.Motion.standard) { showWrapUp = false }
        showToast(result.rolledOver.isEmpty ? "Day closed." : "Day closed. \(result.rolledOver.count) rolled over to tomorrow.")
    }
}
