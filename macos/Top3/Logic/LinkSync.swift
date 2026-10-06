import Foundation

/// What ProTask remembers about one linked event (mirrors EventLink, as a value for planning and tests).
struct LinkState: Equatable {
    var kind: LinkKind
    var contentHash: String?
    var remoteModifiedAt: Date?
    var lastSyncedAt: Date = .distantPast
}

/// The linked event as Calendar has it right now.
struct RemoteState: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var lastModified: Date?

    var fingerprint: String { EventFingerprint.make(title: title, start: start, end: end, isAllDay: isAllDay) }
}

/// Decides, per slot, what to do with a task's events. Pure, so it is unit-tested without EventKit.
enum LinkSync {
    enum Push: Equatable {
        case create     // no event yet
        case update     // event exists but differs from the task
        case remove     // task no longer wants this event
        case keep       // already in line
    }

    /// `specs`: what the task wants. `links`: what we linked. `remote`: those events as Calendar has them
    /// (missing = not found). `remoteMatches`: whether the existing event already equals the spec.
    static func push(specs: [LinkSlot: EventSpec], links: [LinkSlot: LinkState],
                     remoteMatches: [LinkSlot: Bool]) -> [LinkSlot: Push] {
        var out: [LinkSlot: Push] = [:]
        for slot in LinkSlot.allCases {
            let wanted = specs[slot] != nil
            let linked = links[slot] != nil
            switch (wanted, linked) {
            case (false, false): continue
            case (false, true): out[slot] = .remove
            case (true, false): out[slot] = .create
            case (true, true): out[slot] = remoteMatches[slot] == true ? .keep : .update
            }
        }
        return out
    }

    /// Deleting a task removes every event it owns.
    static func deleteTask(links: [LinkSlot: LinkState]) -> [LinkSlot: Push] {
        links.mapValues { _ in .remove }
    }
}

// MARK: Pull (Calendar → task)

extension LinkSync {
    enum Pull: Equatable {
        case unchanged  // Calendar has what we last synced (or there is no baseline yet: the next push sets one)
        case converged  // both sides changed to the same thing
        case pull       // only Calendar changed: apply it to the task
        case remoteWins // both changed, the Calendar edit is newer
        case localWins  // both changed, the ProTask edit is newer
        case deleted    // the event is gone from the ProTask calendar
    }

    /// Who changed what since the last sync, judged by fingerprints: the link remembers the one both sides
    /// agreed on. Only when both moved away from it do modified times decide, and the newest edit wins.
    static func pull(link: LinkState, remote: RemoteState?, local: EventSpec?, localModified: Date?) -> Pull {
        guard let remote else { return .deleted }
        guard let agreed = link.contentHash else { return .unchanged }
        let theirs = remote.fingerprint
        if theirs == agreed { return .unchanged }
        if local?.fingerprint == theirs { return .converged }
        guard let local, local.fingerprint != agreed else { return .pull }
        let remoteTime = remote.lastModified ?? .distantPast
        return remoteTime > (localModified ?? link.lastSyncedAt) ? .remoteWins : .localWins
    }

    /// The task fields a Calendar edit changes.
    /// - due and series events: title, date or time, and the length (as the estimate) of timed events.
    /// - pinned events: the title only. A Top 3 event's day follows the Top 3, so a move is reported
    ///   (`pinnedMoved`) and the event goes back to its day.
    struct RemotePatch: Equatable {
        var title: String?
        var dueDate: Date?
        var hasDueTime: Bool?
        var estimateMinutes: Int?
        var pinnedMoved = false

        var changesTask: Bool { title != nil || dueDate != nil || hasDueTime != nil || estimateMinutes != nil }
    }

    static func remotePatch(kind: LinkKind, remote: RemoteState, task: EventTaskInfo, pinDay: Date?,
                            calendar: Calendar = .current) -> RemotePatch {
        var p = RemotePatch()
        let title = cleanTitle(remote.title)
        if !title.isEmpty, title != task.title { p.title = title }
        if kind == .pinned {
            if let pinDay, !calendar.isDate(remote.start, inSameDayAs: pinDay) { p.pinnedMoved = true }
            return p
        }
        if remote.isAllDay {
            let day = calendar.startOfDay(for: remote.start)
            let sameDay = task.dueDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
            if task.hasDueTime || !sameDay {
                p.dueDate = day
                p.hasDueTime = false
            }
        } else {
            if !task.hasDueTime || task.dueDate != remote.start {
                p.dueDate = remote.start
                p.hasDueTime = true
            }
            let minutes = Int((remote.end.timeIntervalSince(remote.start) / 60).rounded())
            if minutes > 0, minutes <= 24 * 60, minutes != (task.estimateMinutes ?? EventPlanner.defaultMinutes) {
                p.estimateMinutes = minutes
            }
        }
        return p
    }

    /// The task title in an event title, without ProTask's done mark.
    static func cleanTitle(_ s: String) -> String {
        var t = s
        if t.hasPrefix(EventPlanner.doneMark) { t.removeFirst(EventPlanner.doneMark.count) }
        return String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    }

    /// Missing linked events count as deleted, except when every one of several is missing at once:
    /// then the calendar was replaced or hasn't loaded yet, and unscheduling every task would be wrong.
    static func trustMissing(missing: Int, total: Int) -> Bool {
        !(total >= 3 && missing == total)
    }

    /// A short, readable copy of an event version for the sync history.
    static func version(title: String, start: Date, isAllDay: Bool) -> String {
        let when = isAllDay ? DayKey.dateKey(start) : ISO8601DateFormatter().string(from: start)
        return "\(title) (\(when))"
    }
}
