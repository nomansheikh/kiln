import Foundation
import KilnCore
import Observation

/// The Generate screen's state: the draft being edited and the running generation.
@MainActor
@Observable
final class GenerationStore {
    /// Samplers offered in the advanced settings, as named by stable-diffusion.cpp.
    static let samplers = [
        "euler", "euler_a", "heun", "dpm2", "dpm++2s_a", "dpm++2m", "dpm++2mv2",
        "ipndm", "ipndm_v", "lcm", "ddim_trailing", "tcd",
    ]

    var draft = GenerationDraft()
    private(set) var phase: GenerationPhase = .idle
    /// The image on the canvas.
    private(set) var latestImage: GalleryItem?

    private let library: ModelLibrary
    private let gallery: GalleryLibrary
    private let engine: any InferenceEngine
    private var task: Task<Void, Never>?

    init(library: ModelLibrary, gallery: GalleryLibrary, engine: any InferenceEngine) {
        self.library = library
        self.gallery = gallery
        self.engine = engine
        selectDefaultRecipeIfNeeded()
    }

    var selectedRecipe: ModelRecipe? {
        library.recipes.first { $0.id == draft.recipeID }
    }

    var canGenerate: Bool {
        !phase.isBusy && selectedRecipe != nil
            && !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Choosing a model

    /// Selects a model and applies its recommended settings.
    func selectRecipe(_ recipe: ModelRecipe?) {
        draft.recipeID = recipe?.id
        if let defaults = recipe?.defaults {
            draft.apply(defaults)
        }
    }

    /// Picks an installed model when the current choice is missing or was deleted.
    func selectDefaultRecipeIfNeeded() {
        if let id = draft.recipeID, library.installedIDs.contains(id) { return }
        selectRecipe(library.installedRecipes.first)
    }

    // MARK: - Generating

    func generate() {
        guard canGenerate, let recipe = selectedRecipe else { return }
        if draft.randomSeed {
            draft.seed = GenerationRequest.randomSeed()
        }
        let request = GenerationRequest(
            prompt: draft.prompt,
            negativePrompt: draft.negativePrompt,
            width: draft.width,
            height: draft.height,
            steps: draft.steps,
            cfg: draft.cfg,
            sampler: draft.sampler,
            // The recipe's sigma schedule only fits its own step count.
            sigmas: draft.steps == recipe.defaults.steps ? recipe.defaults.sigmas : nil,
            seed: draft.seed
        )

        phase = .starting
        let started = Date()
        task = Task {
            do {
                for try await event in engine.generate(recipe: recipe, request: request) {
                    switch event {
                    case .loadingModel:
                        phase = .loadingModel
                    case .progress(let progress):
                        phase = .running(progress)
                    case .finished(let image):
                        let record = GenerationRecord(
                            recipeID: recipe.id,
                            recipeName: recipe.name,
                            request: request,
                            durationSeconds: Date().timeIntervalSince(started)
                        )
                        latestImage = try gallery.add(image, record: record)
                    }
                }
                phase = .idle
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func dismissError() {
        if case .failed = phase {
            phase = .idle
        }
    }

    /// Frees the memory held by the loaded model.
    func unloadModel() {
        Task { await engine.shutdown() }
    }

    // MARK: - Canvas

    /// Clears the canvas and the prompt. Does nothing while an image is generating.
    func startOver() {
        guard !phase.isBusy else { return }
        latestImage = nil
        draft.prompt = ""
        dismissError()
    }

    func show(_ item: GalleryItem) {
        latestImage = item
    }

    /// Loads a past image's settings into the draft.
    func reuseSettings(of item: GalleryItem) {
        if library.recipes.contains(where: { $0.id == item.record.recipeID }) {
            draft.recipeID = item.record.recipeID
        }
        draft.apply(item.record.request)
    }

    /// Takes a deleted image off the canvas.
    func forget(_ item: GalleryItem) {
        if latestImage?.id == item.id {
            latestImage = nil
        }
    }
}
