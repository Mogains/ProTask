import Foundation

/// What the natural-language parser pulled out of a typed title. Fully local (NSDataDetector + regex).
struct ParsedTask: Equatable {
    var title: String
    var dueDate: Date?
    var hasDueTime = false
    var priority: Priority?
    var estimateMinutes: Int?
    /// The exact phrase the date came from (e.g. "friday 3pm"), so it can be ignored if wrong.
    var datePhrase: String?
    /// Whether the date phrase ends the text, so Backspace can dismiss it.
    var dateAtEnd = false
    /// Lowercased tags from "#tag" words.
    var tags: [String] = []

    var hasExtras: Bool { dueDate != nil || priority != nil || estimateMinutes != nil || !tags.isEmpty }
}

enum TaskParser {
    /// - "!", "!!", "!!!" set low, medium, high priority.
    /// - "30m", "45 min", "1h", "1.5h", "1h30m" set the estimate.
    /// - Dates and times ("friday 3pm", "tomorrow", "oct 12") set the due date.
    /// `ignoring` skips a date phrase the user dismissed.
    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current, ignoring: String? = nil,
                      detectDates: Bool = true) -> ParsedTask {
        var working = text
        var result = ParsedTask(title: text)

        // Tags: "#word" (letters, digits, - and _).
        while let m = firstMatch(#"(?<![\w#])#([\p{L}\p{N}_-]+)"#, in: working) {
            let tag = m.captured.lowercased()
            if !result.tags.contains(tag) { result.tags.append(tag) }
            working.removeSubrange(m.range)
        }

        // Priority: a standalone run of 1-3 "!".
        if let m = firstMatch(#"(?<![!\w])(!{1,3})(?![!\w])"#, in: working) {
            let count = m.captured.count
            result.priority = count == 1 ? .low : count == 2 ? .medium : .high
            working.removeSubrange(m.range)
        }

        // Estimate: "1h30m", "1.5h", "90 min", "30m".
        if let m = firstMatch(#"(?i)\b(\d+(?:\.\d+)?)\s?(h|hr|hrs|hour|hours)(?:\s?(\d+)\s?(m|min|mins|minutes))?\b"#, in: working) {
            let hours = Double(m.groups[0]) ?? 0
            let extra = m.groups.count > 2 ? Int(m.groups[2]) ?? 0 : 0
            result.estimateMinutes = Int((hours * 60).rounded()) + extra
            working.removeSubrange(m.range)
        } else if let m = firstMatch(#"(?i)\b(\d+)\s?(m|min|mins|minutes)\b"#, in: working) {
            result.estimateMinutes = Int(m.groups[0])
            working.removeSubrange(m.range)
        }

        // Date and time.
        if detectDates, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let ns = working as NSString
            let matches = detector.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if let match = matches.first(where: { ns.substring(with: $0.range).caseInsensitiveCompare(ignoring ?? "\u{0}") != .orderedSame }),
               let date = match.date, let range = Range(match.range, in: working) {
                let phrase = String(working[range])
                let hasTime = phraseHasTime(phrase)
                result.datePhrase = phrase
                result.hasDueTime = hasTime
                result.dueDate = hasTime ? date : calendar.startOfDay(for: date)
                result.dateAtEnd = working[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
                working.removeSubrange(range)
            }
        }

        result.title = cleanup(working)
        if result.title.isEmpty { result.title = text.trimmingCharacters(in: .whitespaces) }
        return result
    }

    /// True if the phrase names a time of day, not just a day.
    static func phraseHasTime(_ phrase: String) -> Bool {
        firstMatch(#"(?i)(\d{1,2}(:\d{2})?\s?(am|pm|a\.m\.|p\.m\.))|(\b\d{1,2}:\d{2}\b)|\b(noon|midnight|morning|afternoon|evening|tonight)\b"#, in: phrase) != nil
    }

    private static func cleanup(_ s: String) -> String {
        var out = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        // Drop dangling connectors left behind, e.g. "call mom at" -> "call mom".
        out = out.replacingOccurrences(of: #"(?i)\s+\b(at|on|by|due|for)\s*$"#, with: "", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespaces)
    }

    private struct Match {
        let range: Range<String.Index>
        let captured: String
        let groups: [String]
    }

    private static func firstMatch(_ pattern: String, in s: String) -> Match? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let range = Range(m.range, in: s) else { return nil }
        var groups: [String] = []
        for i in 1..<max(m.numberOfRanges, 1) {
            groups.append(Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "")
        }
        return Match(range: range, captured: groups.first ?? String(s[range]), groups: groups)
    }
}
