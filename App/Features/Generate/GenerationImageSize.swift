import CoreGraphics

/// Pixel dimensions of an image to generate.
struct GenerationImageSize: Hashable {
    let width: Int
    let height: Int

    /// Sizes offered in the composer's size menu.
    static let presets = [
        GenerationImageSize(width: 512, height: 512), GenerationImageSize(width: 768, height: 768),
        GenerationImageSize(width: 1024, height: 1024), GenerationImageSize(width: 1024, height: 1536),
        GenerationImageSize(width: 1536, height: 1024),
    ]

    var title: String { "\(width) × \(height)" }

    /// Width over height, safe for zero dimensions.
    var aspectRatio: CGFloat {
        CGFloat(max(width, 1)) / CGFloat(max(height, 1))
    }
}
