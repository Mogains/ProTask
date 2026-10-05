import Foundation
import SwiftData

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var dueDate: Date?
    /// false = date-only due date
    var hasDueTime: Bool = false
    var priorityRaw: Int = Priority.medium.rawValue
    var estimateMinutes: Int?
    var isCompleted: Bool = false
    var completedAt: Date?
    var listRaw: String = ListKind.haveTo.rawValue
    /// Manual order within the list (lower = higher up).
    var position: Double = 0
    /// 1, 2 or 3 when pinned to Today's Top 3. The task keeps its list so it can return there.
    var topSlot: Int?
    /// Day key the task was pinned for; the morning reset clears older pins.
    var topDay: String?
    var calendarEventID: String?
    var createdAt: Date = Date()
    /// Parking Lot only: when the one-hour reminder fires.
    var remindAt: Date?

    init(title: String, list: ListKind, position: Double) {
        self.title = title
        self.listRaw = list.rawValue
        self.position = position
    }

    var list: ListKind {
        get { ListKind(rawValue: listRaw) ?? .haveTo }
        set { listRaw = newValue.rawValue }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var isIdea: Bool { list == .parkingLot }

    var eventInfo: EventTaskInfo {
        EventTaskInfo(title: title, notes: notes, dueDate: dueDate, hasDueTime: hasDueTime, priority: priority,
                      estimateMinutes: estimateMinutes, isCompleted: isCompleted, topSlot: topSlot, topDay: topDay)
    }

    var statInfo: StatTask {
        StatTask(isCompleted: isCompleted, completedAt: completedAt, dueDate: dueDate, isPinned: topSlot != nil, isIdea: isIdea)
    }
}

extension TaskItem: SortableTask {}

/// Per-list sort mode.
@Model
final class ListSetting {
    @Attribute(.unique) var listRaw: String
    var autoSort: Bool

    init(list: ListKind, autoSort: Bool) {
        self.listRaw = list.rawValue
        self.autoSort = autoSort
    }
}

/// One row per day: drives the streak and the morning prompt.
@Model
final class DayLog {
    @Attribute(.unique) var day: String
    var top3Complete: Bool = false
    var promptDismissed: Bool = false

    init(day: String) {
        self.day = day
    }
}
