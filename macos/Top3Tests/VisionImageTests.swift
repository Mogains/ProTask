import CoreGraphics
import ImageIO
import XCTest

final class VisionImageTests: XCTestCase {
    // MARK: Helpers

    /// Left half red, right half blue (in stored pixel order).
    private func makeImage(width: Int, height: Int, alpha: Bool = false) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: alpha ? 0.5 : 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: alpha ? 0.5 : 1)
        ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return ctx.makeImage()!
    }

    /// Everything a phone camera writes that we must not keep.
    private let sensitive: [CFString: Any] = [
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.3349, kCGImagePropertyGPSLatitudeRef: "N",
                                        kCGImagePropertyGPSLongitude: 122.009, kCGImagePropertyGPSLongitudeRef: "W",
                                        kCGImagePropertyGPSAltitude: 52.0],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05",
                                         kCGImagePropertyExifUserComment: "secret-comment",
                                         kCGImagePropertyExifLensModel: "SecretLens 26mm",
                                         kCGImagePropertyExifBodySerialNumber: "SN123456"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "SecretCam", kCGImagePropertyTIFFModel: "Model Z",
                                         kCGImagePropertyTIFFArtist: "Jane Doe"],
        kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "Cupertino", kCGImagePropertyIPTCByline: ["Jane Doe"]],
    ]

    private func encode(_ image: CGImage, type: String, properties: [CFString: Any] = [:]) -> Data {
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func jpeg(width: Int, height: Int, properties: [CFString: Any] = [:]) -> Data {
        encode(makeImage(width: width, height: height), type: "public.jpeg", properties: properties)
    }

    private func properties(_ data: Data) -> [CFString: Any] {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
    }

    private func size(_ data: Data) -> (Int, Int) {
        let p = properties(data)
        return ((p[kCGImagePropertyPixelWidth] as? Int) ?? -1, (p[kCGImagePropertyPixelHeight] as? Int) ?? -1)
    }

    /// RGBA of the pixel at (x, y), counted from the top left as displayed.
    private func pixel(_ data: Data, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = CGContext(data: &buf, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let i = (y * img.width + x) * 4 // the buffer's first row is the image's top row
        return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]))
    }

    private func assertNoMetadata(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        let p = properties(data)
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary,
                    kCGImagePropertyIPTCDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyMakerAppleDictionary] {
            XCTAssertNil(p[key], "\(key) should be stripped", file: file, line: line)
        }
        XCTAssertTrue((p[kCGImagePropertyOrientation] as? Int).map { $0 == 1 } ?? true, "no rotation left to apply", file: file, line: line)
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        let tags = CGImageSourceCopyMetadataAtIndex(src, 0, nil).flatMap { CGImageMetadataCopyTags($0) as? [Any] } ?? []
        XCTAssertTrue(tags.isEmpty, "no XMP or EXIF tags at all", file: file, line: line)
        for needle in ["Exif\0\0", "secret-comment", "SecretCam", "SecretLens", "SN123456", "Jane Doe", "Cupertino", "2026:01:02"] {
            XCTAssertNil(data.range(of: Data(needle.utf8)), "\(needle) left in the file bytes", file: file, line: line)
        }
    }

    // MARK: Size

    func testDownscalesLongestSideTo2000() throws {
        let out = try VisionImageProcessing.process(jpeg(width: 3000, height: 1500))
        XCTAssertEqual(out.format, .jpeg)
        XCTAssertEqual(out.pixelWidth, 2000)
        XCTAssertEqual(out.pixelHeight, 1000)
        XCTAssertEqual(size(out.image).0, 2000)
        XCTAssertEqual(size(out.image).1, 1000)

        let tall = try VisionImageProcessing.process(jpeg(width: 1200, height: 4000))
        XCTAssertEqual(tall.pixelHeight, 2000)
        XCTAssertEqual(tall.pixelWidth, 600)
        XCTAssertLessThanOrEqual(max(size(tall.image).0, size(tall.image).1), VisionImageProcessing.maxPixelSize)
    }

    func testThumbnailSize() throws {
        let out = try VisionImageProcessing.process(jpeg(width: 3000, height: 1500))
        XCTAssertEqual(out.thumbnailWidth, 480)
        XCTAssertEqual(out.thumbnailHeight, 240)
        XCTAssertEqual(size(out.thumbnail).0, 480)
        XCTAssertEqual(size(out.thumbnail).1, 240)
        XCTAssertLessThan(out.thumbnail.count, out.image.count)
    }

    func testSmallImagesAreNotUpscaled() throws {
        let out = try VisionImageProcessing.process(jpeg(width: 800, height: 600))
        XCTAssertEqual(out.pixelWidth, 800)
        XCTAssertEqual(out.pixelHeight, 600)
        XCTAssertEqual(out.thumbnailWidth, 480)
        XCTAssertEqual(out.thumbnailHeight, 360)

        let tiny = try VisionImageProcessing.process(jpeg(width: 200, height: 100))
        XCTAssertEqual(tiny.pixelWidth, 200)
        XCTAssertEqual(tiny.thumbnailWidth, 200, "the thumbnail is never bigger than the image")
    }

    // MARK: Metadata

    func testStripsExifGPSTIFFAndIPTC() throws {
        let input = jpeg(width: 2400, height: 1600, properties: sensitive)
        // The test image really carries the data we expect to remove.
        let before = properties(input)
        XCTAssertNotNil(before[kCGImagePropertyGPSDictionary])
        XCTAssertNotNil(before[kCGImagePropertyTIFFDictionary])
        XCTAssertNotNil(before[kCGImagePropertyIPTCDictionary])
        XCTAssertEqual((before[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] as? String, "secret-comment")
        XCTAssertNotNil(input.range(of: Data("SecretCam".utf8)))

        let out = try VisionImageProcessing.process(input)
        assertNoMetadata(out.image)
        assertNoMetadata(out.thumbnail)
        // Still a valid picture after the metadata blocks are cut out.
        XCTAssertEqual(pixel(out.image, x: 10, y: 10).r, 255, accuracy: 8)
        XCTAssertEqual(pixel(out.image, x: 1990, y: 10).b, 255, accuracy: 8)
    }

    func testPNGWithAlphaStaysPNGWithoutMetadata() throws {
        var props = sensitive
        props[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: "secret-comment", kCGImagePropertyPNGAuthor: "Jane Doe"]
        let input = encode(makeImage(width: 600, height: 400, alpha: true), type: "public.png", properties: props)
        XCTAssertNotNil(input.range(of: Data("Jane Doe".utf8)), "the test image carries text chunks")

        let out = try VisionImageProcessing.process(input)
        XCTAssertEqual(out.format, .png, "transparency is kept")
        XCTAssertEqual(properties(out.image)[kCGImagePropertyHasAlpha] as? Bool, true)
        assertNoMetadata(out.image)
        assertNoMetadata(out.thumbnail)
        for chunk in MetadataScrubber.pngMetadataChunks {
            XCTAssertNil(out.image.range(of: Data(chunk.utf8)), "\(chunk) chunk left")
        }
    }

    // MARK: Orientation

    func testOrientationIsAppliedBeforeStripping() throws {
        // Stored 300x100, left red / right blue, tagged "rotate 90 clockwise to display".
        var props = sensitive
        props[kCGImagePropertyOrientation] = 6
        let input = jpeg(width: 300, height: 100, properties: props)
        XCTAssertEqual(properties(input)[kCGImagePropertyOrientation] as? Int, 6)

        let out = try VisionImageProcessing.process(input)
        XCTAssertEqual(out.pixelWidth, 100, "turned upright: portrait")
        XCTAssertEqual(out.pixelHeight, 300)
        XCTAssertEqual(size(out.image).0, 100)
        XCTAssertEqual(size(out.image).1, 300)
        assertNoMetadata(out.image)
        // Rotating clockwise puts the stored left (red) on top and the right (blue) at the bottom.
        let top = pixel(out.image, x: 50, y: 20), bottom = pixel(out.image, x: 50, y: 280)
        XCTAssertGreaterThan(top.r, 200)
        XCTAssertLessThan(top.b, 60)
        XCTAssertGreaterThan(bottom.b, 200)
        XCTAssertLessThan(bottom.r, 60)
        XCTAssertEqual(out.thumbnailWidth, 100)
        XCTAssertEqual(out.thumbnailHeight, 300)
    }

    func testOrientedLargeImageIsDownscaledByItsLongestSide() throws {
        var props: [CFString: Any] = [:]
        props[kCGImagePropertyOrientation] = 8 // rotate 90 counter-clockwise
        let out = try VisionImageProcessing.process(jpeg(width: 4000, height: 3000, properties: props))
        XCTAssertEqual(out.pixelWidth, 1500)
        XCTAssertEqual(out.pixelHeight, 2000)
    }

    // MARK: Bad input

    func testRejectsGarbageAndHugeInput() {
        XCTAssertThrowsError(try VisionImageProcessing.process(Data("not an image".utf8))) {
            XCTAssertEqual($0 as? VisionImageProcessing.Failure, .unreadable)
        }
        XCTAssertThrowsError(try VisionImageProcessing.process(Data())) {
            XCTAssertEqual($0 as? VisionImageProcessing.Failure, .unreadable)
        }
        XCTAssertThrowsError(try VisionImageProcessing.process(Data(count: VisionImageProcessing.maxInputBytes + 1))) {
            XCTAssertEqual($0 as? VisionImageProcessing.Failure, .tooLarge)
        }
        XCTAssertNil(MetadataScrubber.scrubJPEG(Data([0xFF, 0xD8, 0x00, 0x01, 0x02])))
        XCTAssertNil(MetadataScrubber.scrubPNG(Data("nope".utf8)))
        XCTAssertNil(MetadataScrubber.scrubJPEG(jpeg(width: 10, height: 10).prefix(30)), "a cut-off file is rejected, not kept")
    }

    // MARK: File names

    func testFileNames() {
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        let jpg = VisionImageFiles.names(for: id, format: .jpeg)
        XCTAssertEqual(jpg.image, "6f9619ff-8b86-d011-b42d-00c04fc964ff.jpg")
        XCTAssertEqual(jpg.thumbnail, "6f9619ff-8b86-d011-b42d-00c04fc964ff-thumb.jpg")
        XCTAssertEqual(VisionImageFiles.names(for: id, format: .png).image, "6f9619ff-8b86-d011-b42d-00c04fc964ff.png")
        XCTAssertTrue(VisionImageFiles.isSafeName(jpg.image))
        for bad in ["", ".", "..", "../Top3.store", "a/b.jpg", "/etc/hosts", ".hidden", "a\\b", "a:b", "a\0b", String(repeating: "x", count: 300)] {
            XCTAssertFalse(VisionImageFiles.isSafeName(bad), bad)
        }
    }
}
