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

    /// Applies a recipe's recommended settings, keeping the prompt.
    mutating func apply(_ defaults: ModelRecipe.GenerationDefaults) {
        width = defaults.width
        height = defaults.height
        steps = defaults.steps
        cfg = defaults.cfg
        sampler = defaults.sampler
    }

    /// Restores everything from a past generation, with its exact seed.
    mutating func apply(_ request: GenerationRequest) {
        prompt = request.prompt
        negativePrompt = request.negativePrompt
        width = request.width
        height = request.height
        steps = request.steps
        cfg = request.cfg
        sampler = request.sampler
        randomSeed = false
        seed = request.seed
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
