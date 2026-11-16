import Foundation

/// What the Generate screen is editing.
public struct GenerationDraft: Equatable, Sendable {
    public var recipeID: String?
    public var prompt = ""
    public var negativePrompt = ""
    public var width = 1024
    public var height = 1024
    public var steps = 20
    public var cfg = 7.0
    public var sampler = "euler"
    public var randomSeed = true
    public var seed: Int64 = 42
    /// An image the prompt should rework instead of starting from nothing.
    public var attachment: URL?
    public var editStrength = EditStrength.balanced
    /// The voice a speech model speaks in. Nil uses the model's own default.
    public var voice: String?
    /// Code of the language a speech model works in. Nil lets the model decide.
    public var language: String?

    public init() {}

    /// Switches to another model: its recommended settings are applied, and a
    /// voice, language or attachment it cannot use is dropped.
    public mutating func select(_ recipe: ModelRecipe?) {
        recipeID = recipe?.id
        if let defaults = recipe?.defaults {
            apply(defaults)
        }
        // Keep the chosen voice when the new model has it too.
        if let recipe, voice.map({ !recipe.voices.contains($0) }) ?? true {
            voice = recipe.defaultVoice
        }
        // A language the new model does not offer goes back to "Auto".
        if let language, recipe?.languages?.contains(language) != true {
            self.language = nil
        }
        // An attachment the new model cannot take would only make the next prompt fail.
        if let attachment, let recipe,
           !recipe.inputKinds.contains(where: { AttachmentLibrary.accepts(attachment, as: $0) }) {
            self.attachment = nil
        }
    }

    /// Applies a recipe's recommended settings, keeping the prompt.
    public mutating func apply(_ defaults: ModelRecipe.ImageDefaults) {
        width = defaults.width
        height = defaults.height
        steps = defaults.steps
        cfg = defaults.cfg
        sampler = defaults.sampler
    }

    /// Restores everything from a past generation, with its exact seed.
    public mutating func apply(_ request: GenerationRequest) {
        prompt = request.prompt
        guard let image = request.image else { return }
        negativePrompt = image.negativePrompt
        width = image.width
        height = image.height
        steps = image.steps
        cfg = image.cfg
        sampler = image.sampler
        randomSeed = false
        seed = image.seed
    }

    /// The request to send to a model: the prompt, the attachment, and the
    /// settings of the model's kind.
    public func request(for recipe: ModelRecipe) -> GenerationRequest {
        var request = GenerationRequest(
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), attachment: attachment, language: language
        )
        if recipe.outputKind == .image {
            request.image = ImageSettings(
                negativePrompt: negativePrompt,
                width: width,
                height: height,
                steps: steps,
                cfg: cfg,
                sampler: sampler,
                // The recipe's sigma schedule only fits its own step count.
                sigmas: steps == recipe.defaults?.steps ? recipe.defaults?.sigmas : nil,
                seed: seed,
                strength: attachment == nil ? nil : editStrength.rawValue
            )
        }
        if recipe.outputKind == .audio {
            request.speech = SpeechSettings(voice: voice)
        }
        return request
    }
}
