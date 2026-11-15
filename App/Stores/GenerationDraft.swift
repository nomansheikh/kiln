import Foundation
import KilnCore

/// What the Generate screen is editing.
struct GenerationDraft: Equatable {
    var recipeID: String?
    var prompt = ""
    var negativePrompt = ""
    var width = 1024
    var height = 1024
    var steps = 20
    var cfg = 7.0
    var sampler = "euler"
    var randomSeed = true
    var seed: Int64 = 42
    /// An image the prompt should rework instead of starting from nothing.
    var attachment: URL?
    var editStrength = EditStrength.balanced
    /// The voice a speech model speaks in. Nil uses the model's own default.
    var voice: String?
    /// Code of the language a speech model works in. Nil lets the model decide.
    var language: String?

    /// Applies a recipe's recommended settings, keeping the prompt.
    mutating func apply(_ defaults: ModelRecipe.ImageDefaults) {
        width = defaults.width
        height = defaults.height
        steps = defaults.steps
        cfg = defaults.cfg
        sampler = defaults.sampler
    }

    /// Restores everything from a past generation, with its exact seed.
    mutating func apply(_ request: GenerationRequest) {
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
    func request(for recipe: ModelRecipe) -> GenerationRequest {
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

/// What the running generation is doing.
enum GenerationPhase: Equatable {
    case idle
    case starting
    case loadingModel
    case running(GenerationProgress)

    var isBusy: Bool { self != .idle }
}
