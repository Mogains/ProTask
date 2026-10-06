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
    /// Legacy single event link. Migrated into `links` on launch; no longer written.
    var calendarEventID: String?
    /// Calendar events this task owns (due / series / pinned). Deleting the task deletes the links.
    @Relationship(deleteRule: .cascade, inverse: \EventLink.task) var links: [EventLink]? = []
    var createdAt: Date = Date()
    /// Parking Lot only: when the one-hour reminder fires.
    var remindAt: Date?
    /// Encoded RecurrenceRule, nil for one-off tasks.
    var recurrenceRaw: String?
    /// Shared by every occurrence of a recurring task.
    var seriesID: UUID?
    /// The occurrence created when this one was completed, so re-checking never duplicates it.
    var nextOccurrenceID: UUID?
    /// Focus time logged against this task, in seconds.
    var actualSeconds: Int = 0
    /// Waiting On only: who it's waiting on.
    var waitingOn: String = ""
    /// Waiting On only: when to follow up.
    var followUpDate: Date?
    /// Space-separated lowercase tags (no "#").
    var tagsRaw: String = ""
    /// Its calendar event was deleted in Calendar. Shown on Today; no event is recreated until it's rescheduled.
    var unscheduled: Bool = false
    /// Last edit in ProTask to something its calendar events show. Decides two-way sync conflicts.
    var modifiedAt: Date?

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
    var isWaiting: Bool { list == .waitingOn }

    var tags: [String] {
        get { tagsRaw.split(separator: " ").map(String.init) }
        set {
            var seen: [String] = []
            for t in newValue.map({ $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "# ,")) }) where !t.isEmpty && !seen.contains(t) {
                seen.append(t)
            }
            tagsRaw = seen.joined(separator: " ")
        }
    }

    var recurrence: RecurrenceRule? {
        get { RecurrenceRule(encoded: recurrenceRaw) }
        set { recurrenceRaw = newValue?.encoded }
    }

    func link(_ slot: LinkSlot) -> EventLink? { (links ?? []).first { $0.kind.slot == slot } }

    var eventInfo: EventTaskInfo {
        EventTaskInfo(title: title, notes: notes, dueDate: dueDate, hasDueTime: hasDueTime, priority: priority,
                      estimateMinutes: estimateMinutes, isCompleted: isCompleted, topSlot: topSlot, topDay: topDay,
                      recurrence: recurrence, unscheduled: unscheduled)
    }

    var statInfo: StatTask {
        StatTask(isCompleted: isCompleted, completedAt: completedAt, dueDate: dueDate, isPinned: topSlot != nil, isIdea: isIdea || isWaiting)
    }
}

extension TaskItem: SortableTask {}

/// One finished focus session (feeds actual time and the weekly review).
@Model
final class FocusSession {
    var id: UUID = UUID()
    var taskID: UUID?
    var taskTitle: String = ""
    var start: Date = Date()
    var seconds: Int = 0

    init(taskID: UUID?, taskTitle: String, start: Date, seconds: Int) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.start = start
        self.seconds = seconds
    }
}

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
    /// Morning planning was finished or skipped for this day.
    var planningDone: Bool = false
    /// The day was closed from the evening wrap-up.
    var dayClosed: Bool = false
    /// Comma-separated ids of unfinished picks that rolled over into this day.
    var rolledOverRaw: String = ""

    init(day: String) {
        self.day = day
    }
}

/// One calendar event owned by a task, with what we knew about it at the last sync.
@Model
final class EventLink {
    var id: UUID = UUID()
    var kindRaw: String = LinkKind.due.rawValue
    /// EKEvent.eventIdentifier
    var eventIdentifier: String = ""
    /// EKEvent.calendarItemExternalIdentifier: survives the identifier changes some accounts make when re-syncing
    var externalIdentifier: String?
    /// EventFingerprint of title/start/end at the last sync, when both sides agreed
    var contentHash: String?
    /// EKEvent.lastModifiedDate at the last sync
    var remoteModifiedAt: Date?
    var lastSyncedAt: Date = Date()
    var task: TaskItem?

    init(kind: LinkKind, eventIdentifier: String) {
        self.kindRaw = kind.rawValue
        self.eventIdentifier = eventIdentifier
    }

    var kind: LinkKind {
        get { LinkKind(rawValue: kindRaw) ?? .due }
        set { kindRaw = newValue.rawValue }
    }

    var state: LinkState {
        LinkState(kind: kind, contentHash: contentHash, remoteModifiedAt: remoteModifiedAt, lastSyncedAt: lastSyncedAt)
    }
}

/// What two-way sync overwrote or removed, so nothing is lost silently. The newest 200 are kept.
@Model
final class SyncRecord {
    var id: UUID = UUID()
    var at: Date = Date()
    var taskID: UUID?
    var taskTitle: String = ""
    /// "conflict" | "deleted-in-calendar" | "pinned-moved"
    var reason: String = ""
    /// "calendar" | "protask": whose version was kept
    var winner: String?
    /// The version that was not kept
    var lost: String = ""

    init(taskID: UUID?, taskTitle: String, reason: String, winner: String?, lost: String) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.reason = reason
        self.winner = winner
        self.lost = lost
    }
}
