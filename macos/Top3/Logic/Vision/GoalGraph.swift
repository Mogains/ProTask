import Foundation

/// One dependency between goals: `downstream` depends on `upstream`, so the upstream goal comes first.
struct GoalEdge: Hashable, Codable {
    let upstream: UUID
    let downstream: UUID
}

/// The goal dependency graph. Kept acyclic: a goal can never end up depending on itself.
enum GoalGraph {
    /// True when adding `edge` would close a loop (including linking a goal to itself).
    static func wouldCreateCycle(adding edge: GoalEdge, to edges: [GoalEdge]) -> Bool {
        edge.upstream == edge.downstream || downstream(of: edge.downstream, in: edges).contains(edge.upstream)
    }

    /// Every goal that depends on `id`, directly or through others.
    static func downstream(of id: UUID, in edges: [GoalEdge]) -> Set<UUID> {
        reach(from: id, next: Dictionary(grouping: edges, by: \.upstream).mapValues { $0.map(\.downstream) })
    }

    /// Every goal `id` depends on, directly or through others.
    static func upstream(of id: UUID, in edges: [GoalEdge]) -> Set<UUID> {
        reach(from: id, next: Dictionary(grouping: edges, by: \.downstream).mapValues { $0.map(\.upstream) })
    }

    private static func reach(from start: UUID, next: [UUID: [UUID]]) -> Set<UUID> {
        var seen: Set<UUID> = []
        var stack = next[start] ?? []
        while let id = stack.popLast() {
            guard seen.insert(id).inserted else { continue }
            stack += next[id] ?? []
        }
        return seen
    }
}
