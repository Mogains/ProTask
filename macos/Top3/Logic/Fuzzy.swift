import Foundation

/// Subsequence fuzzy matching with bonuses for prefixes, word starts and consecutive letters.
enum Fuzzy {
    /// nil when `query` isn't a subsequence of `text`; otherwise higher is better.
    static func score(_ query: String, in text: String) -> Int? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !q.isEmpty else { return 0 }
        let t = Array(text.lowercased())
        var score = 0, qi = 0, last = -2
        for (i, c) in t.enumerated() where qi < q.count && c == q[qi] {
            var s = 1
            if i == 0 { s += 8 }
            else if !t[i - 1].isLetter && !t[i - 1].isNumber { s += 6 }
            if i == last + 1 { s += 4 }
            score += s
            last = i
            qi += 1
        }
        guard qi == q.count else { return nil }
        if text.lowercased().hasPrefix(query.lowercased()) { score += 10 }
        return score - t.count / 10
    }
}
