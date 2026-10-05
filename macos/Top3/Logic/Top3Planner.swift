import Foundation

/// Rules for the three Top 3 slots. Nothing here can produce a fourth pinned task.
enum Top3Planner {
    static let slots = [1, 2, 3]
    static let fullMessage = "Your Top 3 is full. Finish or remove one first."

    struct Occupant: Equatable {
        var slot: Int
        var taskID: UUID
    }

    struct Displaced: Equatable {
        var taskID: UUID
        /// The slot the displaced task moves to (a swap), or nil to send it back to its list.
        var toSlot: Int?
    }

    enum Plan: Equatable {
        case assign(slot: Int, displaced: Displaced?)
        case full
        case invalidSlot
    }

    /// - No slot requested (star button): first free slot, or `.full`.
    /// - Slot requested (drop on a slot, Cmd+1/2/3): that slot; its occupant swaps or goes back.
    static func plan(occupants: [Occupant], taskID: UUID, requested: Int? = nil) -> Plan {
        if let r = requested, !slots.contains(r) { return .invalidSlot }
        let current = occupants.first { $0.taskID == taskID }?.slot

        guard let requested else {
            if let current { return .assign(slot: current, displaced: nil) }
            let taken = Set(occupants.map(\.slot))
            guard let free = slots.first(where: { !taken.contains($0) }) else { return .full }
            return .assign(slot: free, displaced: nil)
        }

        guard let occupant = occupants.first(where: { $0.slot == requested }), occupant.taskID != taskID else {
            return .assign(slot: requested, displaced: nil)
        }
        return .assign(slot: requested, displaced: Displaced(taskID: occupant.taskID, toSlot: current))
    }

    /// Applies a plan to the occupants. Used by tests to check the invariant.
    static func apply(_ plan: Plan, to occupants: [Occupant], taskID: UUID) -> [Occupant] {
        guard case let .assign(slot, displaced) = plan else { return occupants }
        var next = occupants.filter { $0.taskID != taskID && $0.taskID != displaced?.taskID }
        next.append(Occupant(slot: slot, taskID: taskID))
        if let d = displaced, let to = d.toSlot { next.append(Occupant(slot: to, taskID: d.taskID)) }
        return next.sorted { $0.slot < $1.slot }
    }
}
