import AppKit
import SwiftUI

struct RunningFocus: Codable, Equatable {
    var taskID: UUID?
    var title: String
    var start: Date
    var seconds: Int

    var end: Date { start.addingTimeInterval(TimeInterval(seconds)) }
    func remaining(at now: Date = Date()) -> Int { max(0, Int(end.timeIntervalSince(now).rounded(.up))) }

    static let defaultsKey = "runningFocus"
    static let notificationID = "focus-end"

    static func load() -> RunningFocus? {
        UserDefaults.standard.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(RunningFocus.self, from: $0) }
    }

    static func store(_ f: RunningFocus?) {
        if let f, let data = try? JSONEncoder().encode(f) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }
}

struct CustomFocusRequest: Identifiable {
    let id = UUID()
    var taskID: UUID?
}

/// Focus timer: start from a task, log actual time, notify at the end, survive restarts.
extension AppModel {
    static let focusMinutesKey = "focusMinutes"

    var defaultFocusMinutes: Int {
        let v = UserDefaults.standard.object(forKey: Self.focusMinutesKey) as? Int ?? 25
        return min(max(v, 1), 240)
    }

    func startFocus(on t: TaskItem?, minutes: Int? = nil) {
        if focus != nil { stopFocus() }
        let mins = min(max(minutes ?? defaultFocusMinutes, 1), 240)
        let f = RunningFocus(taskID: t?.id, title: t?.title ?? "Focus", start: Date(), seconds: mins * 60)
        focus = f
        RunningFocus.store(f)
        notifications.scheduleOnce(identifier: RunningFocus.notificationID, title: "Focus session done",
                                   body: "\(mins) minutes on \(f.title).", at: f.end)
        armFocusEndTimer()
        showToast("Focusing for \(mins) minutes.")
    }

    func toggleFocusForSelection() {
        if focus != nil { stopFocus() } else { startFocus(on: task(selectedTaskID)) }
    }

    /// Stops early (or on completion) and logs the time actually spent.
    func stopFocus(completed: Bool = false) {
        guard let f = focus else { return }
        let spent = completed ? f.seconds : min(f.seconds, max(0, Int(Date().timeIntervalSince(f.start))))
        if spent >= 60 {
            context.insert(FocusSession(taskID: f.taskID, taskTitle: f.title, start: f.start, seconds: spent))
            if let t = task(f.taskID) { t.actualSeconds += spent }
        }
        focus = nil
        RunningFocus.store(nil)
        focusEndTimer?.invalidate()
        if !completed { notifications.cancel(identifier: RunningFocus.notificationID) }
        save()
        if completed {
            NSSound(named: "Glass")?.play()
            showToast("Focus session done: \(Fmt.minutes(spent / 60) ?? "") on \(f.title).")
        }
    }

    func finishFocusIfDue() {
        if let f = focus, Date() >= f.end { stopFocus(completed: true) }
    }

    /// After a restart: finish a session that ended while closed, or keep counting down.
    func resumeFocus() {
        finishFocusIfDue()
        if focus != nil { armFocusEndTimer() }
    }

    private func armFocusEndTimer() {
        focusEndTimer?.invalidate()
        guard let f = focus else { return }
        focusEndTimer = Timer.scheduledTimer(withTimeInterval: max(0.5, f.end.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishFocusIfDue() }
        }
    }
}
