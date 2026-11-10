import Foundation
import KilnCore
import Observation

/// The Generate screen's state: the draft being edited and the thread of
/// prompts and images produced from it.
@MainActor
@Observable
final class GenerationStore {
    /// Samplers offered in the advanced settings, as named by stable-diffusion.cpp.
    static let samplers = [
        "euler", "euler_a", "heun", "dpm2", "dpm++2s_a", "dpm++2m", "dpm++2mv2",
        "ipndm", "ipndm_v", "lcm", "ddim_trailing", "tcd",
    ]

    var draft = GenerationDraft()
    /// The conversation on screen, oldest first.
    private(set) var turns: [GenerationTurn] = []
    /// The saved chat the thread belongs to. Nil until the first prompt is sent.
    private(set) var chatID: UUID?
    /// Progress of the turn that is running, if any.
    private(set) var phase: GenerationPhase = .idle
    /// A rough look at the image being generated, when the model can provide one.
    private(set) var preview: GeneratedImage?

    private let library: ModelLibrary
    private let gallery: GalleryLibrary
    private let chats: ChatLibrary
    private let engine: any InferenceEngine
    private var task: Task<Void, Never>?

    init(library: ModelLibrary, gallery: GalleryLibrary, chats: ChatLibrary, engine: any InferenceEngine) {
        self.library = library
        self.gallery = gallery
        self.chats = chats
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

    /// The most recent image in the thread.
    var latestImage: GalleryItem? {
        turns.last { $0.image != nil }?.image
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

    /// Sends the draft's prompt: it moves into the thread and the field empties.
    func generate() {
        guard canGenerate, let recipe = selectedRecipe else { return }
        if draft.randomSeed {
            draft.seed = GenerationRequest.randomSeed()
        }
        let request = GenerationRequest(
            prompt: draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
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
        let turn = GenerationTurn(prompt: request.prompt, width: request.width, height: request.height)
        turns.append(turn)
        draft.prompt = ""
        phase = .starting
        saveChat()

        task = Task {
            let outcome = await run(request, with: recipe)
            finish(turn.id, as: outcome)
        }
    }

    /// Runs the prompt of an earlier turn again with the current settings.
    func regenerate(_ turn: GenerationTurn) {
        guard !phase.isBusy else { return }
        draft.prompt = turn.prompt
        generate()
    }

    func cancel() {
        task?.cancel()
    }

    /// Frees the memory held by the loaded model.
    func unloadModel() {
        Task { await engine.shutdown() }
    }

    private func run(_ request: GenerationRequest, with recipe: ModelRecipe) async -> GenerationTurn.State {
        let started = Date()
        do {
            for try await event in engine.generate(recipe: recipe, request: request) {
                switch event {
                case .loadingModel:
                    phase = .loadingModel
                case .progress(let progress):
                    phase = .running(progress)
                case .preview(let image):
                    preview = image
                case .finished(let image):
                    let record = GenerationRecord(
                        recipeID: recipe.id,
                        recipeName: recipe.name,
                        request: request,
                        durationSeconds: Date().timeIntervalSince(started)
                    )
                    return .finished(try gallery.add(image, record: record))
                }
            }
            return .failed("The engine finished without producing an image.")
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func finish(_ id: UUID, as state: GenerationTurn.State) {
        phase = .idle
        preview = nil
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[index].state = state
        saveChat()
    }

    /// Writes the thread to its chat, creating the chat on the first prompt.
    private func saveChat() {
        guard let first = turns.first else { return }
        let id = chatID ?? UUID()
        chatID = id
        var chat = chats.chat(id) ?? Chat(id: id, title: Chat.defaultTitle(for: first.prompt))
        chat.turns = turns.map(\.saved)
        chat.updatedAt = Date()
        chats.save(chat)
    }

    // MARK: - Thread

    /// Starts a new, empty chat. Does nothing while an image is generating.
    func startOver() {
        guard !phase.isBusy else { return }
        chatID = nil
        turns = []
        draft.prompt = ""
    }

    /// Shows a saved chat. Does nothing while an image is generating.
    func open(_ chat: Chat) {
        guard !phase.isBusy, chat.id != chatID else { return }
        chatID = chat.id
        turns = chat.turns.map { GenerationTurn($0, images: gallery.items) }
    }

    /// Loads a past image's settings into the draft.
    func reuseSettings(of item: GalleryItem) {
        if library.recipes.contains(where: { $0.id == item.record.recipeID }) {
            draft.recipeID = item.record.recipeID
        }
        draft.apply(item.record.request)
    }

    /// Removes a deleted image from the thread.
    func forget(_ item: GalleryItem) {
        guard turns.contains(where: { $0.image?.id == item.id }) else { return }
        turns.removeAll { $0.image?.id == item.id }
        saveChat()
    }

    #if DEBUG
    /// Fills the thread with sample turns for snapshots.
    func loadPreview(turns: [GenerationTurn], phase: GenerationPhase, preview: GeneratedImage? = nil) {
        self.turns = turns
        self.phase = phase
        self.preview = preview
    }
    #endif
}
