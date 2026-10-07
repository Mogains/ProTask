import AppKit
import Foundation
import UniformTypeIdentifiers

/// Vision image files: ~/Library/Application Support/ProTask/VisionImages, folder 0700 and files 0600.
/// Runs on a throwaway store (TOP3_STORE_PATH) use a VisionImages folder next to that store instead.
/// Everything stored has been through VisionImageProcessing: downscaled, upright, and without metadata.
/// Nothing here logs, and error messages never contain paths.
struct VisionImageStore: Sendable {
    let folder: URL

    static var standard: VisionImageStore { VisionImageStore(folder: defaultFolder()) }

    static func defaultFolder(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let store = environment["TOP3_STORE_PATH"], !store.isEmpty {
            return URL(fileURLWithPath: store).deletingLastPathComponent().appending(path: "VisionImages", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "ProTask/VisionImages", directoryHint: .isDirectory)
    }

    /// A processed image saved to disk, ready to become a GoalImage.
    struct Stored: Sendable, Equatable {
        let id: UUID
        let fileName: String
        let thumbnailFileName: String
        let pixelWidth: Int
        let pixelHeight: Int

        var fileNames: [String] { [fileName, thumbnailFileName] }
    }

    enum ImportError: LocalizedError, Equatable {
        case unreadable, tooLarge, nothingToPaste, couldNotSave

        var errorDescription: String? {
            switch self {
            case .unreadable: "That image couldn't be read."
            case .tooLarge: "That image is too large to add."
            case .nothingToPaste: "There's no image on the clipboard."
            case .couldNotSave: "Couldn't save the image."
            }
        }
    }

    /// What an image import starts from.
    enum Source: Sendable {
        case file(URL)
        case data(Data)
    }

    // MARK: Import

    func importImage(_ source: Source) throws -> Stored {
        switch source {
        case let .file(url): try importImage(from: url)
        case let .data(data): try importImage(data: data)
        }
    }

    func importImage(from url: URL) throws -> Stored {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= VisionImageProcessing.maxInputBytes else { throw ImportError.tooLarge }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw ImportError.unreadable }
        return try importImage(data: data)
    }

    func importImage(data: Data) throws -> Stored {
        let output: VisionImageProcessing.Output
        do { output = try VisionImageProcessing.process(data) } catch VisionImageProcessing.Failure.tooLarge {
            throw ImportError.tooLarge
        } catch {
            throw ImportError.unreadable
        }
        try prepareFolder()
        let id = UUID()
        let names = VisionImageFiles.names(for: id, format: output.format)
        do {
            try write(output.image, named: names.image)
            try write(output.thumbnail, named: names.thumbnail)
        } catch {
            delete([names.image, names.thumbnail])
            throw ImportError.couldNotSave
        }
        return Stored(id: id, fileName: names.image, thumbnailFileName: names.thumbnail,
                      pixelWidth: output.pixelWidth, pixelHeight: output.pixelHeight)
    }

    /// The image on a pasteboard: an image file that was copied in Finder, or image data (PNG, TIFF, JPEG, HEIC).
    @MainActor
    static func pasteboardImage(_ pasteboard: NSPasteboard = .general) -> Source? {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL])?.first {
            return .file(url)
        }
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, .init(UTType.jpeg.identifier), .init(UTType.heic.identifier)]
        for type in types {
            if let data = pasteboard.data(forType: type) { return .data(data) }
        }
        return nil
    }

    // MARK: Files

    /// The file's location, or nil for a name that isn't a plain file name (for example from an edited backup).
    func url(for fileName: String) -> URL? {
        VisionImageFiles.isSafeName(fileName) ? folder.appending(path: fileName, directoryHint: .notDirectory) : nil
    }

    func delete(_ fileNames: [String]) {
        for name in fileNames {
            if let url = url(for: name) { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Creates the folder owner-only, and locks down anything already in it.
    func prepareFolder() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: NSNumber(value: FilePermissions.folder)])
        } catch {
            throw ImportError.couldNotSave
        }
        FilePermissions.lockDown(folder)
    }

    private func write(_ data: Data, named name: String) throws {
        guard let url = url(for: name),
              FileManager.default.createFile(atPath: url.path, contents: data,
                                             attributes: [.posixPermissions: NSNumber(value: FilePermissions.file)])
        else { throw ImportError.couldNotSave }
        FilePermissions.lockFile(url)
    }
}
