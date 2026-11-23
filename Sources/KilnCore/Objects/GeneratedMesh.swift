import Foundation

/// A 3D object a model made: a GLB file's bytes, as the engine wrote them.
public struct GeneratedMesh: Sendable, Hashable {
    public var glb: Data

    public init(glb: Data) {
        self.glb = glb
    }
}

/// Settings of one generated 3D object. The defaults are the engine's own.
public struct MeshSettings: Codable, Sendable, Equatable {
    /// How finely the object is worked out, as the side of the grid it is built in.
    public enum Detail: Int, Codable, Sendable, CaseIterable, Identifiable {
        /// The quickest, and the one that needs the least memory.
        case standard = 512
        /// Sharper edges and finer texture, for about three times the wait.
        case fine = 1024
        /// The finest the model goes. Slow, and it needs the most memory.
        case ultra = 1536

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .standard: "Standard"
            case .fine: "Fine"
            case .ultra: "Ultra"
            }
        }

        public var explanation: String {
            switch self {
            case .standard: "A few minutes, least memory"
            case .fine: "Sharper detail, about three times as long"
            case .ultra: "The finest detail, slow and memory-hungry"
            }
        }
    }

    /// How the object is cut out of its picture.
    public enum Cutout: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Keep a picture's own transparency; otherwise let the model find the object.
        case automatic = "auto"
        /// Always let the background-removal model find the object.
        case model = "birefnet"
        /// Treat a plain white background as empty. Quick, but it also removes bright highlights.
        case whiteBackground = "threshold"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .automatic: "Automatic"
            case .model: "Find the object"
            case .whiteBackground: "White background"
            }
        }
    }

    public static let defaultSteps = 12
    public static let defaultGuidance = 7.5
    public static let stepsRange = 4...50
    public static let guidanceRange = 1.0...15.0
    public static let textureSizes = [1024, 2048, 4096]

    public var detail: Detail
    public var seed: Int64
    /// Sampling steps of each stage. More is slower and, up to a point, cleaner.
    public var steps: Int
    /// How closely the overall form follows the picture.
    public var structureGuidance: Double
    /// How closely the surface follows the picture.
    public var shapeGuidance: Double
    public var cutout: Cutout
    /// Side of the colour image in pixels. Nil lets the engine choose by detail.
    public var textureSize: Int?

    public init(
        detail: Detail = .standard, seed: Int64, steps: Int = MeshSettings.defaultSteps,
        structureGuidance: Double = MeshSettings.defaultGuidance, shapeGuidance: Double = MeshSettings.defaultGuidance,
        cutout: Cutout = .automatic, textureSize: Int? = nil
    ) {
        self.detail = detail
        self.seed = seed
        self.steps = steps
        self.structureGuidance = structureGuidance
        self.shapeGuidance = shapeGuidance
        self.cutout = cutout
        self.textureSize = textureSize
    }

    /// The settings with every value inside what the engine accepts.
    public var clamped: MeshSettings {
        var copy = self
        copy.steps = min(max(steps, Self.stepsRange.lowerBound), Self.stepsRange.upperBound)
        copy.structureGuidance = min(max(structureGuidance, Self.guidanceRange.lowerBound), Self.guidanceRange.upperBound)
        copy.shapeGuidance = min(max(shapeGuidance, Self.guidanceRange.lowerBound), Self.guidanceRange.upperBound)
        if let textureSize, !Self.textureSizes.contains(textureSize) { copy.textureSize = nil }
        return copy
    }
}
