// Turns the app icon artwork into every size the asset catalog needs.
// Usage: swift scripts/make-icon.swift scripts/app-icon.png App/Assets.xcassets/AppIcon.appiconset
//
// The artwork is one rounded square on a transparent background. Its corners and
// proportions are close to the macOS icon shape but not exact, and macOS puts an
// icon that does not match the shape on a light backing plate. So the artwork is
// fitted into the exact shape here: an 824 px rounded square centred on a 1024 px
// canvas, with the standard shadow. The artwork's own margin and shadow are dropped.
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2,
      let source = NSImage(contentsOfFile: arguments[0])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-icon.swift <artwork.png> <AppIcon.appiconset>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])

/// The artwork as RGBA bytes, rows from the top.
let width = source.width, height = source.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
pixels.withUnsafeMutableBytes { buffer in
    let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
}

/// The box around the fully opaque pixels: the square itself, without its shadow. Top-left origin.
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= 250 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
precondition(maxX >= 0, "the artwork has no opaque pixels")
let body = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)

/// The square's own colour near its top edge, to fill the corners the artwork leaves empty.
let sample = (Int(body.minY + body.height * 0.05) * width + Int(body.midX)) * 4
let fill = CGColor(
    srgbRed: CGFloat(pixels[sample]) / 255, green: CGFloat(pixels[sample + 1]) / 255,
    blue: CGFloat(pixels[sample + 2]) / 255, alpha: 1
)

func drawIcon(in context: CGContext) {
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(platePath)
    context.setFillColor(fill)
    context.fillPath()
    context.restoreGState()

    context.addPath(platePath)
    context.clip()
    // The square is stretched to cover the plate, a little past its edges so the artwork's
    // own rim does not show. Core Graphics counts y from the bottom; the box is from the top.
    let target = plate.insetBy(dx: -8, dy: -8)
    let scaleX = target.width / body.width, scaleY = target.height / body.height
    context.interpolationQuality = .high
    context.draw(source, in: CGRect(
        x: target.minX - body.minX * scaleX,
        y: target.minY - (CGFloat(height) - body.maxY) * scaleY,
        width: CGFloat(width) * scaleX,
        height: CGFloat(height) * scaleY
    ))
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try png(pixels: points * scale).write(to: output.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon images to \(output.path)")
