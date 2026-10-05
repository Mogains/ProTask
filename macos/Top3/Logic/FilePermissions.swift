import Foundation

/// Owner-only access for everything ProTask keeps on disk: the database, backups and the widget file.
/// Folders 0700 and files 0600, so other user accounts on the Mac can't read your tasks.
enum FilePermissions {
    static let file: Int16 = 0o600
    static let folder: Int16 = 0o700

    /// Locks down `dir` and every regular file directly inside it. Returns the paths it changed.
    @discardableResult
    static func lockDown(_ dir: URL, fm: FileManager = .default) -> [String] {
        var changed: [String] = []
        if set(folder, on: dir.path, fm: fm) { changed.append(dir.lastPathComponent) }
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey])) ?? []
        for url in items {
            let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if v?.isRegularFile == true, set(file, on: url.path, fm: fm) { changed.append(url.lastPathComponent) }
        }
        return changed
    }

    static func lockFile(_ url: URL, fm: FileManager = .default) {
        set(file, on: url.path, fm: fm)
    }

    @discardableResult
    private static func set(_ mode: Int16, on path: String, fm: FileManager) -> Bool {
        guard let cur = (try? fm.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber else { return false }
        if cur.int16Value & 0o777 == mode { return false }
        return (try? fm.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path)) != nil
    }
}
