// Draws the Kiln app icon and writes every size the asset catalog needs.
// Usage: swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// An arch standing on the line `baseY`: straight sides topped by a half circle.
func arch(centerX: CGFloat, baseY: CGFloat, width: CGFloat, height: CGFloat) -> CGPath {
    let radius = width / 2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: centerX - radius, y: baseY))
    path.addLine(to: CGPoint(x: centerX - radius, y: baseY + height - radius))
    path.addArc(center: CGPoint(x: centerX, y: baseY + height - radius), radius: radius, startAngle: .pi, endAngle: 0, clockwise: true)
    path.addLine(to: CGPoint(x: centerX + radius, y: baseY))
    path.closeSubpath()
    return path
}

func drawIcon(in context: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // The standard macOS icon shape: an 824 pt rounded square centred on a 1024 pt canvas.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, alpha: 0.35))
    context.addPath(platePath)
    context.setFillColor(color(0x10222B))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(platePath)
    context.clip()
    let background = CGGradient(colorsSpace: space, colors: [color(0x1D4354), color(0x0B1418)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // The glow the fire throws onto the floor and wall.
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFF8A3D, alpha: 0.55), color(0xFF8A3D, alpha: 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 300), startRadius: 0, endCenter: CGPoint(x: 512, y: 300), endRadius: 430, options: [])

    // The kiln's brick face.
    context.addPath(arch(centerX: 512, baseY: 262, width: 468, height: 520))
    context.setFillColor(color(0x2C4D5C))
    context.fillPath()
    context.addPath(arch(centerX: 512, baseY: 262, width: 468, height: 520))
    context.setStrokeColor(color(0x4F7C8F, alpha: 0.9))
    context.setLineWidth(10)
    context.strokePath()

    // The opening, lit from inside.
    let mouth = arch(centerX: 512, baseY: 262, width: 300, height: 380)
    context.saveGState()
    context.addPath(mouth)
    context.clip()
    let fire = CGGradient(
        colorsSpace: space,
        colors: [color(0xFFF3C4), color(0xFFC04A), color(0xFF6A2A), color(0x8E1F16)] as CFArray,
        locations: [0, 0.3, 0.65, 1]
    )!
    context.drawRadialGradient(fire, startCenter: CGPoint(x: 512, y: 290), startRadius: 0, endCenter: CGPoint(x: 512, y: 330), endRadius: 360, options: [.drawsAfterEndLocation])
    context.restoreGState()
    context.addPath(mouth)
    context.setStrokeColor(color(0x14262E))
    context.setLineWidth(14)
    context.strokePath()

    // The floor line the kiln stands on.
    context.setFillColor(color(0x14262E))
    context.fill(CGRect(x: 100, y: 100, width: 824, height: 162))
    context.restoreGState()
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
