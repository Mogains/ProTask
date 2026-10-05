import Foundation

/// The lists a task can live in. Parking Lot holds quick ideas that remind you after an hour.
enum ListKind: String, CaseIterable, Codable, Identifiable {
    case haveTo, niceTo, waitingOn, parkingLot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .haveTo: "Have to do"
        case .niceTo: "Nice to do"
        case .waitingOn: "Waiting On"
        case .parkingLot: "Parking Lot"
        }
    }

    /// The two regular lists (not the Parking Lot).
    static let taskLists: [ListKind] = [.haveTo, .niceTo]
}

enum Priority: Int, CaseIterable, Codable, Identifiable {
    case high = 0, medium = 1, low = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}
