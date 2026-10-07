import CoreGraphics
import Foundation
import ImageIO

/// Turns an imported picture into what Vision stores: at most 2000px on the longest side, turned upright,
/// re-encoded with no metadata (no EXIF, GPS, TIFF camera data, IPTC or XMP), plus a small thumbnail.
enum VisionImageProcessing {
    static let maxPixelSize = 2000
    static let thumbnailPixelSize = 480
    static let quality = 0.85
    static let thumbnailQuality = 0.8
    /// Refused before decoding, so a huge file can't exhaust memory.
    static let maxInputBytes = 100 * 1024 * 1024
    static let maxInputPixels = 150_000_000

    enum Format: String, Equatable {
        case jpeg, png

        var fileExtension: String { self == .jpeg ? "jpg" : "png" }
        var typeIdentifier: String { self == .jpeg ? "public.jpeg" : "public.png" }
    }

    struct Output: Equatable {
        var image: Data
        var thumbnail: Data
        var format: Format
        var pixelWidth: Int
        var pixelHeight: Int
        var thumbnailWidth: Int
        var thumbnailHeight: Int
    }

    enum Failure: Error, Equatable {
        case unreadable, tooLarge, encodingFailed
    }

    static func process(_ data: Data) throws -> Output {
        guard data.count <= maxInputBytes else { throw Failure.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else { throw Failure.unreadable }
        guard width <= maxInputPixels / height else { throw Failure.tooLarge }

        // Never upscale: a small picture keeps its size, only turned upright and re-encoded.
        let longest = max(width, height)
        guard let full = render(source, maxSide: min(maxPixelSize, longest)),
              let thumb = render(source, maxSide: min(thumbnailPixelSize, longest))
        else { throw Failure.unreadable }

        let format: Format = hasAlpha(full) ? .png : .jpeg
        return Output(image: try encode(full, as: format, quality: quality),
                      thumbnail: try encode(thumb, as: format, quality: thumbnailQuality),
                      format: format, pixelWidth: full.width, pixelHeight: full.height,
                      thumbnailWidth: thumb.width, thumbnailHeight: thumb.height)
    }

    /// Decodes at most `maxSide` pixels on the longest side, with the EXIF orientation applied to the pixels,
    /// so nothing depends on the orientation tag that is dropped on encoding.
    private static func render(_ source: CGImageSource, maxSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, // never the small embedded preview
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: true
        default: false
        }
    }

    /// Encodes only the pixels (no source properties are passed on), then removes the few technical tags ImageIO adds.
    private static func encode(_ image: CGImage, as format: Format, quality: Double) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, format.typeIdentifier as CFString, 1, nil) else { throw Failure.encodingFailed }
        let options: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: quality] : [:]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest), let clean = MetadataScrubber.scrub(out as Data, format: format) else {
            throw Failure.encodingFailed
        }
        return clean
    }
}

/// Removes metadata blocks from an encoded JPEG or PNG without touching the pixels.
/// Keeps only what decoding needs: JFIF, the color profile and Adobe color info for JPEG; image, palette,
/// color and transparency chunks for PNG. Returns nil for anything it can't parse, so callers never keep an unscrubbed file.
enum MetadataScrubber {
    static func scrub(_ data: Data, format: VisionImageProcessing.Format) -> Data? {
        format == .jpeg ? scrubJPEG(data) : scrubPNG(data)
    }

    /// Drops APP1 (EXIF, XMP), APP3...APP13 (IPTC and Photoshop), APP15 and comments.
    /// Keeps APP0 (JFIF), APP2 (ICC profile) and APP14 (Adobe color transform).
    static func scrubJPEG(_ data: Data) -> Data? {
        let b = [UInt8](data)
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var out: [UInt8] = [0xFF, 0xD8]
        var i = 2
        while i + 1 < b.count {
            guard b[i] == 0xFF else { return nil }
            let marker = b[i + 1]
            switch marker {
            case 0xFF:
                i += 1 // fill byte
            case 0xDA, 0xD9:
                out += b[i...] // start of scan (or end): the rest is image data
                return Data(out)
            case 0x01, 0xD0...0xD7:
                out += b[i..<(i + 2)]
                i += 2
            default:
                guard i + 3 < b.count else { return nil }
                let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
                let end = i + 2 + length
                guard length >= 2, end <= b.count else { return nil }
                let isMetadata = marker == 0xE1 || (0xE3...0xED).contains(marker) || marker == 0xEF || marker == 0xFE
                if !isMetadata { out += b[i..<end] }
                i = end
            }
        }
        return nil
    }

    static let pngMetadataChunks: Set<String> = ["eXIf", "tEXt", "zTXt", "iTXt", "tIME"]
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Drops eXIf, text and timestamp chunks.
    static func scrubPNG(_ data: Data) -> Data? {
        let b = [UInt8](data)
        guard b.count > pngSignature.count, Array(b[0..<pngSignature.count]) == pngSignature else { return nil }
        var out = pngSignature
        var i = pngSignature.count
        while i + 12 <= b.count {
            let length = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
            let end = i + 12 + length
            guard length >= 0, end <= b.count, let type = String(bytes: b[(i + 4)..<(i + 8)], encoding: .ascii) else { return nil }
            if !pngMetadataChunks.contains(type) { out += b[i..<end] }
            i = end
            if type == "IEND" { return Data(out) }
        }
        return nil
    }
}

/// File names in the VisionImages folder. Only plain names are stored (never paths), and names coming back
/// from a backup are checked so they can never point outside the folder.
enum VisionImageFiles {
    static func names(for id: UUID, format: VisionImageProcessing.Format) -> (image: String, thumbnail: String) {
        let base = id.uuidString.lowercased()
        return ("\(base).\(format.fileExtension)", "\(base)-thumb.\(format.fileExtension)")
    }

    /// A single file name inside the folder: no separators, no parent references, not hidden.
    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255 && !name.hasPrefix(".")
            && !name.contains("/") && !name.contains("\\") && !name.contains(":") && !name.contains("\0")
    }
}
