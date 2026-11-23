import Foundation

/// The request `kiln-trellis` takes.
extension EngineMessage {
    private struct ShapeCommand: Encodable {
        let type = "shape"
        /// The folder holding every file of the model, under the names the engine knows them by.
        var models: String
        /// Which model the folder holds: `trellis` or `pixal3d`.
        var family: String
        /// The picture of the object, as a PNG file.
        var image: String
        /// The GLB file the helper writes.
        var output: String
        /// Side of the grid the object is built in: 512, 1024 or 1536.
        var resolution: Int
        var seed: UInt32
        var steps: Int
        var structureGuidance: Double
        var shapeGuidance: Double
        /// `auto`, `birefnet` or `threshold`.
        var cutout: String
        /// Side of the colour image in pixels. Zero lets the engine choose.
        var textureSize: Int

        enum CodingKeys: String, CodingKey {
            case type, models, family, image, output, resolution, seed, steps, cutout
            case structureGuidance = "structure_guidance"
            case shapeGuidance = "shape_guidance"
            case textureSize = "texture_size"
        }
    }

    static func shapeCommand(models: URL, family: String, image: URL, output: URL, settings: MeshSettings) throws -> Data {
        let settings = settings.clamped
        return try line(ShapeCommand(
            models: models.path, family: family, image: image.path, output: output.path,
            resolution: settings.detail.rawValue, seed: UInt32(truncatingIfNeeded: settings.seed), steps: settings.steps,
            structureGuidance: settings.structureGuidance, shapeGuidance: settings.shapeGuidance,
            cutout: settings.cutout.rawValue, textureSize: settings.textureSize ?? 0
        ))
    }
}
