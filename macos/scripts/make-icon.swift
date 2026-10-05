// Draws the app icon: a near-black rounded square with three grey checklist rows.
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
    ctx.setFillColor(NSColor(white: 0.11, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.08).cgColor)
    ctx.setLineWidth(4 * k)
    ctx.strokePath()

    // Three rows: circle + line. The first is checked.
    let rows: [CGFloat] = [640, 500, 360]
    for (i, y) in rows.enumerated() {
        let cy = y * k
        let r = 44 * k
        let cx = 300 * k
        let circle = CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)
        if i == 0 {
            ctx.setFillColor(NSColor(white: 0.82, alpha: 1).cgColor)
            ctx.fillEllipse(in: circle)
            ctx.setStrokeColor(NSColor(white: 0.11, alpha: 1).cgColor)
            ctx.setLineWidth(14 * k)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: cx - 20 * k, y: cy + 1 * k))
            ctx.addLine(to: CGPoint(x: cx - 4 * k, y: cy - 16 * k))
            ctx.addLine(to: CGPoint(x: cx + 22 * k, y: cy + 18 * k))
            ctx.strokePath()
        } else {
            ctx.setStrokeColor(NSColor(white: 0.55, alpha: 1).cgColor)
            ctx.setLineWidth(12 * k)
            ctx.strokeEllipse(in: circle.insetBy(dx: 6 * k, dy: 6 * k))
        }
        let lineWidths: [CGFloat] = [330, 270, 210]
        ctx.setStrokeColor(NSColor(white: i == 0 ? 0.82 : 0.45, alpha: 1).cgColor)
        ctx.setLineWidth(30 * k)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 400 * k, y: cy))
        ctx.addLine(to: CGPoint(x: (400 + lineWidths[i]) * k, y: cy))
        ctx.strokePath()
    }
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
