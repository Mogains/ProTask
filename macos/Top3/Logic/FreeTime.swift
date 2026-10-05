import Foundation

enum FreeTime {
    /// Free gaps between busy intervals inside [dayStart, dayEnd], starting no earlier than `now`.
    static func gaps(busy: [DateInterval], dayStart: Date, dayEnd: Date, now: Date, minMinutes: Int = 15) -> [DateInterval] {
        let from = max(dayStart, now)
        guard from < dayEnd else { return [] }
        let relevant = busy
            .filter { $0.end > from && $0.start < dayEnd }
            .sorted { $0.start < $1.start }

        var result: [DateInterval] = []
        var cursor = from
        func add(_ s: Date, _ e: Date) {
            let end = min(e, dayEnd)
            if end.timeIntervalSince(s) >= Double(minMinutes) * 60 { result.append(DateInterval(start: s, end: end)) }
        }
        for b in relevant {
            if b.start > cursor { add(cursor, b.start) }
            cursor = max(cursor, b.end)
        }
        add(cursor, dayEnd)
        return result
    }
}
