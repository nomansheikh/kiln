import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Everything needed to reproduce a generated image.
public struct GenerationRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var recipeID: String
    public var recipeName: String
    public var request: GenerationRequest
    public var durationSeconds: Double?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        recipeID: String,
        recipeName: String,
        request: GenerationRequest,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.recipeID = recipeID
        self.recipeName = recipeName
        self.request = request
        self.durationSeconds = durationSeconds
    }

    /// The settings as one block of text, in the layout other Stable Diffusion tools read.
    public var parametersText: String {
        var lines = [request.prompt]
        if !request.negativePrompt.isEmpty {
            lines.append("Negative prompt: \(request.negativePrompt)")
        }
        lines.append([
            "Steps: \(request.steps)",
            "Sampler: \(request.sampler)",
            "CFG scale: \(request.cfg.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))))",
            "Seed: \(request.seed)",
            "Size: \(request.width)x\(request.height)",
            "Model: \(recipeName)",
        ].joined(separator: ", "))
        return lines.joined(separator: "\n")
    }
}

public enum ImageCodecError: Error, LocalizedError {
    case invalidPixels
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPixels: "The image data is not valid."
        case .encodingFailed: "The image could not be saved as a PNG."
        }
    }
}

/// Writes generated images as PNG files that carry their own settings.
public enum ImageCodec {
    /// Chunk other Stable Diffusion tools read for the settings.
    static let parametersKeyword = "parameters"
    /// Chunk holding the full record as JSON.
    static let recordKeyword = "kiln"

    public static func cgImage(from image: GeneratedImage) throws -> CGImage {
        guard image.width > 0, image.height > 0, [1, 3, 4].contains(image.channels),
              image.pixels.count == image.width * image.height * image.channels,
              let provider = CGDataProvider(data: image.pixels as CFData)
        else {
            throw ImageCodecError.invalidPixels
        }
        let colorSpace = image.channels == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
        let alpha: CGImageAlphaInfo = image.channels == 4 ? .last : .none
        guard let cgImage = CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * image.channels,
            bytesPerRow: image.width * image.channels,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw ImageCodecError.invalidPixels
        }
        return cgImage
    }

    /// PNG data with the record embedded as text chunks.
    public static func pngData(for image: GeneratedImage, record: GenerationRecord) throws -> Data {
        let cgImage = try cgImage(from: image)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(record), as: UTF8.self)

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageCodecError.encodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination),
              let tagged = PNGText.inserting(
                  [(parametersKeyword, record.parametersText), (recordKeyword, json)],
                  into: data as Data
              )
        else {
            throw ImageCodecError.encodingFailed
        }
        return tagged
    }

    /// The record embedded in a PNG written by Kiln, if any.
    public static func record(in file: URL) -> GenerationRecord? {
        guard let json = PNGText.entries(in: file)[recordKeyword] else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GenerationRecord.self, from: Data(json.utf8))
    }
}
