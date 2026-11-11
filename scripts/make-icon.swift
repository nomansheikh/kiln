// Turns the app icon artwork into every size the asset catalog needs.
// Usage: swift scripts/make-icon.swift scripts/app-icon.png App/Assets.xcassets/AppIcon.appiconset
//
// The artwork is one rounded square on a transparent background, with a soft shadow.
// It is scaled so the square is 824 px wide and centred on a 1024 px canvas, which is
// the standard macOS icon shape, whatever margin the artwork came with.
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2,
      let source = NSImage(contentsOfFile: arguments[0])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-icon.swift <artwork.png> <AppIcon.appiconset>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])

/// The box around the fully opaque pixels: the square itself, without its shadow. Top-left origin.
func opaqueBounds(of image: CGImage) -> CGRect {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= 250 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    precondition(maxX >= 0, "the artwork has no opaque pixels")
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let body = opaqueBounds(of: source)
let scale = 824 / body.width

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    // Core Graphics counts y from the bottom; the bounds were measured from the top.
    let bodyBottom = CGFloat(source.height) - body.maxY
    context.draw(source, in: CGRect(
        x: 512 - (body.midX * scale),
        y: 512 - ((bodyBottom + body.height / 2) * scale),
        width: CGFloat(source.width) * scale,
        height: CGFloat(source.height) * scale
    ))
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
print("Wrote \(images.count) icon images to \(output.path); the square was \(Int(body.width)) by \(Int(body.height)) px in the artwork")
