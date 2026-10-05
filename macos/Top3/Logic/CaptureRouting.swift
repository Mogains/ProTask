import Foundation

/// Quick-add prefixes: none goes to Have to do, "~" to Nice to do, "?" to the Parking Lot.
enum CaptureRouting {
    static func route(_ raw: String) -> (list: ListKind, text: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("~") { return (.niceTo, String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        if trimmed.hasPrefix("?") { return (.parkingLot, String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        return (.haveTo, trimmed)
    }
}
