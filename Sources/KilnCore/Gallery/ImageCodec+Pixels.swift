import CoreGraphics
import Foundation
import ImageIO

extension ImageCodec {
    /// Raw 8-bit RGB pixels of an image file at exactly `width` by `height`.
    ///
    /// The image is scaled to fill the size and cropped around its centre, so
    /// nothing is stretched when its proportions differ from the target.
    public static func rgbPixels(of file: URL, width: Int, height: Int) throws -> Data {
        guard width > 0, height > 0,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else {
            throw ImageCodecError.invalidPixels
        }

        let scale = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.interpolationQuality = .high
        // Transparent areas become white rather than black.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(
            x: (CGFloat(width) - drawn.width) / 2,
            y: (CGFloat(height) - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        ))

        guard let buffer = context.data else { throw ImageCodecError.invalidPixels }
        let rgbx = UnsafeBufferPointer(start: buffer.assumingMemoryBound(to: UInt8.self), count: width * height * 4)
        var rgb = Data(count: width * height * 3)
        rgb.withUnsafeMutableBytes { destination in
            var out = 0
            for pixel in stride(from: 0, to: rgbx.count, by: 4) {
                destination[out] = rgbx[pixel]
                destination[out + 1] = rgbx[pixel + 1]
                destination[out + 2] = rgbx[pixel + 2]
                out += 3
            }
        }
        return rgb
    }
}
