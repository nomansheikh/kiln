import Foundation

/// What the 3D screen holds, and what follows from it: the request the model is
/// sent, and whether it can be sent. A plain value, so those rules are tested.
public struct MeshDraft: Sendable, Equatable {
    public var recipeID: String?
    /// The picture the object is made from.
    public var image: URL?
    /// A description of the object, for when there is no picture: an image model draws one first.
    public var prompt = ""
    public var detail = MeshSettings.Detail.standard
    public var randomSeed = true
    public var seed: Int64 = 42
    public var steps = MeshSettings.defaultSteps
    public var structureGuidance = MeshSettings.defaultGuidance
    public var shapeGuidance = MeshSettings.defaultGuidance
    public var cutout = MeshSettings.Cutout.automatic
    /// Side of the colour image in pixels. Nil lets the engine choose by detail.
    public var textureSize: Int?

    public init() {}

    /// True when a setting under "Advanced" differs from the engine's own.
    public var hasCustomSettings: Bool {
        steps != MeshSettings.defaultSteps || structureGuidance != MeshSettings.defaultGuidance
            || shapeGuidance != MeshSettings.defaultGuidance || cutout != .automatic || textureSize != nil
    }

    /// Puts the settings under "Advanced" back to the engine's own.
    public mutating func resetAdvanced() {
        steps = MeshSettings.defaultSteps
        structureGuidance = MeshSettings.defaultGuidance
        shapeGuidance = MeshSettings.defaultGuidance
        cutout = .automatic
        textureSize = nil
    }

    public var settings: MeshSettings {
        MeshSettings(
            detail: detail, seed: seed, steps: steps, structureGuidance: structureGuidance, shapeGuidance: shapeGuidance,
            cutout: cutout, textureSize: textureSize
        ).clamped
    }

    /// What is added to a description so that the picture drawn from it suits the
    /// 3D model: one object, all of it in view, with nothing behind it.
    public static let pictureGuidance = "a single object, shown whole and centred, on a plain white background, soft even studio lighting"

    /// What sending does next.
    public enum Step: Equatable, Sendable {
        /// Draw a picture of what is described, to be approved before it is made into an object.
        case picture
        /// Make the object from the picture.
        case object
    }

    /// What sending would do, or nil when nothing can be sent. A picture comes
    /// first: with one, the description is not used.
    public func nextStep(objectRecipe: ModelRecipe?, imageRecipe: ModelRecipe?) -> Step? {
        guard objectRecipe?.outputKind == .mesh else { return nil }
        if image != nil { return .object }
        let described = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return described && imageRecipe?.outputKind == .image && imageRecipe?.defaults != nil ? .picture : nil
    }

    /// The request for a picture of what is described, with the image model's own
    /// settings and a square frame. Nil without a description or for a model that draws no images.
    public func pictureRequest(for recipe: ModelRecipe, seed: Int64) -> GenerationRequest? {
        let described = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !described.isEmpty, recipe.outputKind == .image, let defaults = recipe.defaults else { return nil }
        var settings = ImageSettings(defaults: defaults, seed: seed)
        let side = min(settings.width, settings.height)
        settings.width = side
        settings.height = side
        // The recipe's sigma schedule is kept: the step count is unchanged.
        return GenerationRequest(prompt: "\(described), \(Self.pictureGuidance)", image: settings)
    }

    /// True when there is a model and a picture to give it.
    public func canSend(with recipe: ModelRecipe?) -> Bool {
        recipe?.outputKind == .mesh && image != nil
    }

    /// The request to send. Nil without a picture.
    public var request: GenerationRequest? {
        image.map { GenerationRequest(prompt: "", attachment: $0, mesh: settings) }
    }

    /// Switches to another model. The settings are the engine's, so they stay,
    /// except a level of detail the model does not have.
    public mutating func select(_ recipe: ModelRecipe?) {
        recipeID = recipe?.id
        if let details = recipe?.meshDetails, !details.contains(detail), let first = details.first {
            detail = first
        }
    }

    /// Puts back what a past object was made with, with its exact seed.
    public mutating func reuse(_ request: GenerationRequest) {
        if let attachment = request.attachment { image = attachment }
        guard let settings = request.mesh else { return }
        detail = settings.detail
        randomSeed = false
        seed = settings.seed
        steps = settings.steps
        structureGuidance = settings.structureGuidance
        shapeGuidance = settings.shapeGuidance
        cutout = settings.cutout
        textureSize = settings.textureSize
    }

    /// Roughly how much memory a run needs, in gigabytes, measured with the
    /// Q4 files. Nil where it has not been measured.
    public static func measuredMemoryGB(for detail: MeshSettings.Detail) -> Double? {
        switch detail {
        case .standard: 6
        case .fine: 8
        case .ultra: nil
        }
    }
}
