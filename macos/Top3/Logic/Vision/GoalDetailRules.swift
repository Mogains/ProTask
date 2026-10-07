import Foundation

// MARK: - Time left

enum GoalTimeLeft {
    /// "3 months left", "12 days left", "Due today", "5 days past", or nil without a target or once closed.
    static func describe(target: Date?, status: GoalStatus, today: Date, calendar: Calendar = .current) -> String? {
        guard let target, status.isOpen else { return nil }
        let from = calendar.startOfDay(for: today), to = calendar.startOfDay(for: target)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        if days == 0 { return "Due today" }
        if days < 0 { return days == -1 ? "1 day past" : "\(-days) days past" }
        if days < 14 { return days == 1 ? "1 day left" : "\(days) days left" }
        if days < 70 { return "\(days / 7) weeks left" }
        let months = calendar.dateComponents([.month], from: from, to: to).month ?? 0
        if months < 24 { return "\(max(months, 2)) months left" }
        return "\(months / 12) years left"
    }
}

// MARK: - Image gallery

/// Moving through a goal's images in the full-size viewer.
enum GalleryIndex {
    /// One step back or forward, stopping at the ends.
    static func step(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }

    /// What to show after removing the image at `index`: the next one, or the one before when it was the last.
    /// Nil when nothing is left.
    static func afterRemoving(at index: Int, count: Int) -> Int? {
        let remaining = count - 1
        guard remaining > 0 else { return nil }
        return min(max(index, 0), remaining - 1)
    }

    /// Accessibility and the viewer's counter: "2 of 5".
    static func label(_ index: Int, count: Int) -> String { "\(index + 1) of \(count)" }
}
