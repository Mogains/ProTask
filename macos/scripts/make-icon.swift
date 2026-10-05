// Draws the ProTask app icon: a near-black rounded square with the grey ProTask mark.
// Usage: swift scripts/make-icon.swift Top3/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = s / 1024

    // macOS icon grid: 824pt body inset by 100pt, corner radius ~185pt.
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let path = CGPath(roundedRect: body, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x16 / 255, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.08).cgColor)
    ctx.setLineWidth(4 * k)
    ctx.strokePath()

    // The ProTask mark: a square outline with one solid corner block (same glyph as the "today" icon).
    let side: CGFloat = 430 * k
    let stroke: CGFloat = 50 * k
    let mark = CGRect(x: 512 * k - side / 2, y: 512 * k - side / 2, width: side, height: side)
    ctx.setStrokeColor(NSColor(srgbRed: 0xD4 / 255, green: 0xD4 / 255, blue: 0xD8 / 255, alpha: 1).cgColor)
    ctx.setLineWidth(stroke)
    ctx.setLineJoin(.miter)
    ctx.addPath(CGPath(roundedRect: mark.insetBy(dx: stroke / 2, dy: stroke / 2), cornerWidth: 18 * k, cornerHeight: 18 * k, transform: nil))
    ctx.strokePath()
    let block: CGFloat = 112 * k
    let inset: CGFloat = stroke + 48 * k
    ctx.setFillColor(NSColor(srgbRed: 0x8A / 255, green: 0x8A / 255, blue: 0x90 / 255, alpha: 1).cgColor)
    ctx.fill(CGRect(x: mark.maxX - inset - block, y: mark.maxY - inset - block, width: block, height: block))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! draw(size: px).write(to: outDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon images to \(outDir.path)")
