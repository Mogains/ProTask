import Foundation

/// Decides what the morning reset (or closing the day) does with Top 3 picks.
enum Rollover {
    struct Pin: Equatable {
        var id: UUID
        var topDay: String?
        var isCompleted: Bool
    }

    struct Result: Equatable {
        /// Leave the Top 3 (their day is over).
        var unpin: [UUID]
        /// Unfinished picks that go back to their list and get offered again in morning planning.
        var rolledOver: [UUID]
    }

    /// Pins from a day other than `today` are cleared; the unfinished ones roll over.
    static func plan(pins: [Pin], today: String) -> Result {
        let stale = pins.filter { $0.topDay != today }
        return Result(unpin: stale.map(\.id), rolledOver: stale.filter { !$0.isCompleted }.map(\.id))
    }

    /// Closing the day early: every unfinished pick rolls over; finished ones stay for the record.
    static func closeDay(pins: [Pin]) -> Result {
        let open = pins.filter { !$0.isCompleted }.map(\.id)
        return Result(unpin: open, rolledOver: open)
    }

    static func encode(_ ids: [UUID]) -> String { ids.map(\.uuidString).joined(separator: ",") }
    static func decode(_ raw: String) -> [UUID] { raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
}
