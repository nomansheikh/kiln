import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageCodec {
    /// Writes any image Kiln can read as a PNG, keeping its transparency. A
    /// helper is handed this copy, since it reads PNG and cannot reach the original.
    public static func writePNG(of file: URL, to destination: URL) throws {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ImageCodecError.invalidPixels }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw ImageCodecError.encodingFailed }
    }
}
