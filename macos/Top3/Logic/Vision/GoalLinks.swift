import Foundation

// MARK: - Goal to goal links

/// A new link seen from the goal being edited.
enum GoalLinkRelation: String, CaseIterable, Identifiable {
    /// The goal needs the other one first: the other goal is upstream.
    case dependsOn
    /// The other goal needs this one first: this goal is upstream.
    case neededFor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dependsOn: "Depends on"
        case .neededFor: "Needed for"
        }
    }

    func edge(goal: UUID, other: UUID) -> GoalEdge {
        switch self {
        case .dependsOn: GoalEdge(upstream: other, downstream: goal)
        case .neededFor: GoalEdge(upstream: goal, downstream: other)
        }
    }
}

/// Whether a link may be added, and why not.
enum GoalLinkCheck: Equatable {
    case allowed
    case sameGoal
    case alreadyLinked
    case wouldLoop

    var isAllowed: Bool { self == .allowed }

    /// A short reason for a choice that can't be picked.
    var reason: String? {
        switch self {
        case .allowed: nil
        case .sameGoal: "This goal"
        case .alreadyLinked: "Already linked"
        case .wouldLoop: "Would make a loop"
        }
    }
}

/// The rules for linking goals. The graph stays acyclic: no self-links, no loops through other goals.
enum GoalLinks {
    static func check(goal: UUID, other: UUID, relation: GoalLinkRelation, edges: [GoalEdge]) -> GoalLinkCheck {
        if goal == other { return .sameGoal }
        let edge = relation.edge(goal: goal, other: other)
        if edges.contains(edge) { return .alreadyLinked }
        return GoalGraph.wouldCreateCycle(adding: edge, to: edges) ? .wouldLoop : .allowed
    }

    /// The goals `id` depends on directly, in edge order, without repeats.
    static func dependsOn(_ id: UUID, edges: [GoalEdge]) -> [UUID] {
        unique(edges.filter { $0.downstream == id && $0.upstream != id }.map(\.upstream))
    }

    /// The goals that depend on `id` directly, in edge order, without repeats.
    static func neededFor(_ id: UUID, edges: [GoalEdge]) -> [UUID] {
        unique(edges.filter { $0.upstream == id && $0.downstream != id }.map(\.downstream))
    }

    /// Every candidate with its verdict: allowed ones first, then the rest, each group keeping the given order.
    static func candidates(for goal: UUID, relation: GoalLinkRelation, among ids: [UUID],
                           edges: [GoalEdge]) -> [(id: UUID, check: GoalLinkCheck)] {
        let checked = unique(ids).filter { $0 != goal }.map { (id: $0, check: check(goal: goal, other: $0, relation: relation, edges: edges)) }
        return checked.filter(\.check.isAllowed) + checked.filter { !$0.check.isAllowed }
    }

    private static func unique(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}

// MARK: - Picker search

/// Narrowing a picker list by typed text: fuzzy matches best first; everything, in order, for an empty query.
enum LinkSearch {
    static func filter<T>(_ items: [T], query: String, title: (T) -> String) -> [T] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.enumerated()
            .compactMap { i, item in Fuzzy.score(q, in: title(item)).map { (i, item, $0) } }
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
            .map(\.1)
    }
}
