import Foundation

/// What the desktop widget shows. The app writes it after every change; the widget only reads it.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable {
        var slot: Int
        var title: String
        var done: Bool
    }

    var updated: Date
    var day: String
    var items: [Item]
    /// Newest Parking Lot ideas (titles) and the total count. Optional so older files still decode.
    var ideas: [String]? = nil
    var ideaCount: Int? = nil

    var doneCount: Int { items.filter(\.done).count }

    static let fileName = "widget.json"

    /// ~/Library/Application Support/ProTask/widget.json using the real home folder,
    /// so the sandboxed widget (which has a read-only exception for that folder) finds the same file.
    static var url: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appending(path: "Library/Application Support/ProTask", directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    func write() {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(self), (try? data.write(to: Self.url, options: .atomic)) != nil else { return }
        // Owner-only, like the database (the widget runs as the same user, so it can still read it).
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: Self.url.path)
    }

    static let placeholder = WidgetSnapshot(updated: Date(), day: "", items: [
        Item(slot: 1, title: "Finish quarterly report", done: false),
        Item(slot: 2, title: "Pay rent", done: true),
        Item(slot: 3, title: "Gym", done: false),
    ], ideas: ["Newsletter for the team", "Try a standing desk", "Weekend trip ideas"], ideaCount: 5)
}
