import Foundation

// MARK: - Goal kinds

/// What a Vision item is: a goal, a milestone on the way to one, or a habit target (a routine to keep up).
enum GoalType: String, CaseIterable, Codable, Identifiable {
    case goal, milestone, habitTarget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goal: "Goal"
        case .milestone: "Milestone"
        case .habitTarget: "Habit target"
        }
    }
}

/// Where a goal stands. Idea, planned and active are open; done and dropped are closed.
enum GoalStatus: String, CaseIterable, Codable, Identifiable {
    case idea, planned, active, done, dropped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idea: "Idea"
        case .planned: "Planned"
        case .active: "Active"
        case .done: "Done"
        case .dropped: "Dropped"
        }
    }

    /// Still in play: not finished and not dropped.
    var isOpen: Bool { self != .done && self != .dropped }
}

/// Manual progress is the number you set. Automatic progress comes from the metric, or the linked tasks.
enum ProgressMode: String, CaseIterable, Codable, Identifiable {
    case manual, auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "Manual"
        case .auto: "Automatic"
        }
    }
}

// MARK: - Timeline palette

/// The timeline palette: eight muted hues that sit quietly on both the dark and the light greys.
/// Timelines store the name; Theme.Vision maps it to its ColorTokens pair.
enum TimelineColor: String, CaseIterable, Codable, Identifiable {
    case slate, mist, sage, sand, clay, rose, plum, stone

    static let fallback: TimelineColor = .slate

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Unknown names (a newer backup, a typo) fall back instead of failing.
    init(named name: String) {
        self = TimelineColor(rawValue: name) ?? .fallback
    }

    /// A color for a new timeline: the least used one, earliest in the palette on a tie.
    static func next(after used: [TimelineColor]) -> TimelineColor {
        let counts = Dictionary(used.map { ($0, 1) }, uniquingKeysWith: +)
        return allCases.min { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? fallback
    }
}

// MARK: - Templates

/// Starting points for a new timeline.
struct TimelineTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let details: String
    let color: TimelineColor

    static let all: [TimelineTemplate] = [
        TimelineTemplate(id: "career", name: "Career", details: "Roles, skills and the work you want to be known for.", color: .slate),
        TimelineTemplate(id: "education", name: "Education", details: "Courses, degrees and things you want to learn.", color: .plum),
        TimelineTemplate(id: "health", name: "Health", details: "Fitness, sleep, food and how you want to feel.", color: .sage),
        TimelineTemplate(id: "finance", name: "Finance", details: "Savings, debt and the numbers behind your plans.", color: .sand),
        TimelineTemplate(id: "projects", name: "Projects", details: "Things you are building, making or shipping.", color: .clay),
        TimelineTemplate(id: "life", name: "Life", details: "Places, people and experiences.", color: .rose),
    ]

    static func named(_ id: String) -> TimelineTemplate? { all.first { $0.id == id } }
}
