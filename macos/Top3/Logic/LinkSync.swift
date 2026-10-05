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
