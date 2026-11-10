import AppKit
import ImageIO
import SwiftUI

/// A downsampled image loaded off the main thread, for grids and lists.
struct Thumbnail: View {
    let url: URL
    var maxPixelSize = 400

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Theme.card
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            }
        }
        .task(id: url) {
            image = await Self.load(url, maxPixelSize: maxPixelSize)
        }
    }

    private struct Loaded: @unchecked Sendable {
        let image: CGImage
    }

    private static func load(_ url: URL, maxPixelSize: Int) async -> NSImage? {
        let loaded = await Task.detached(priority: .utility) { () -> Loaded? in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return Loaded(image: image)
        }.value
        return loaded.map { NSImage(cgImage: $0.image, size: .zero) }
    }
}
