import Foundation

/// One block of a goal's notes. Inline styling (bold, italic, code, links) stays in the text,
/// for AttributedString(markdown:) to render line by line.
enum NoteBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(text: String, indent: Int)
    case numbered(number: Int, text: String, indent: Int)
    case task(done: Bool, text: String, indent: Int)
    case quote(String)
    case code(String)
    case rule
    case paragraph(String)
}

/// A small Markdown block reader for goal notes: headings, lists, checklists, quotes, code fences, rules
/// and paragraphs. SwiftUI's Text only renders inline Markdown, so blocks are split here.
enum NotesMarkdown {
    static func blocks(_ source: String) -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        var quoting = false

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }

        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for raw in lines {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let wasQuoting = quoting
            quoting = false
            if var open = code {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    open.append(line)
                    code = open
                }
                continue
            }
            if trimmed.hasPrefix("```") { flush(); code = []; continue }
            if trimmed.isEmpty { flush(); continue }
            let indent = (line.count - line.drop { $0 == " " }.count) / 2
            if let heading = heading(trimmed) { flush(); blocks.append(heading); continue }
            if isRule(trimmed) { flush(); blocks.append(.rule); continue }
            if trimmed.hasPrefix(">") {
                flush()
                let text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                quoting = true
                if wasQuoting, case let .quote(previous)? = blocks.last {
                    blocks[blocks.count - 1] = .quote(previous + "\n" + text)
                } else {
                    blocks.append(.quote(text))
                }
                continue
            }
            if let item = listItem(trimmed, indent: indent) { flush(); blocks.append(item); continue }
            paragraph.append(trimmed)
        }
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> NoteBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : .heading(level: min(hashes, 3), text: text)
    }

    private static func isRule(_ line: String) -> Bool {
        let chars = line.filter { $0 != " " }
        guard chars.count >= 3, let first = chars.first, "-*_".contains(first) else { return false }
        return chars.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String, indent: Int) -> NoteBlock? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            let text = String(line.dropFirst(2))
            for (box, done) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where text.hasPrefix(box) {
                return .task(done: done, text: String(text.dropFirst(box.count)), indent: indent)
            }
            return .bullet(text: text, indent: indent)
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 4, let n = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return .numbered(number: n, text: String(rest.dropFirst(2)), indent: indent)
    }
}
