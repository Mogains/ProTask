import XCTest

final class FilePermissionsTests: XCTestCase {
    func testLocksFolderAndFilesToOwnerOnly() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "perm-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        defer { try? fm.removeItem(at: dir) }
        for name in ["Top3.store", "Top3.store-wal", "widget.json"] {
            fm.createFile(atPath: dir.appending(path: name).path, contents: Data("x".utf8), attributes: [.posixPermissions: 0o644])
        }
        func mode(_ p: String) -> Int { ((try? fm.attributesOfItem(atPath: p))?[.posixPermissions] as? NSNumber)?.intValue ?? -1 }

        let changed = FilePermissions.lockDown(dir)
        XCTAssertEqual(changed.count, 4)
        XCTAssertEqual(mode(dir.path), 0o700)
        for name in ["Top3.store", "Top3.store-wal", "widget.json"] { XCTAssertEqual(mode(dir.appending(path: name).path), 0o600) }
        XCTAssertTrue(FilePermissions.lockDown(dir).isEmpty, "second run changes nothing")
    }
}
