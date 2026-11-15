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
    /// The model currently held in memory by the engine, if any.
    private(set) var loadedRecipeID: String?

    let library: ModelLibrary
    let attachments: AttachmentLibrary
    private let gallery: GalleryLibrary
    private let audio: AudioLibrary
    private let chats: ChatLibrary
    private let engine: any InferenceEngine
    private var task: Task<Void, Never>?

    init(
        library: ModelLibrary,
        gallery: GalleryLibrary,
        audio: AudioLibrary,
        chats: ChatLibrary,
        attachments: AttachmentLibrary,
        engine: any InferenceEngine
    ) {
        self.library = library
        self.gallery = gallery
        self.audio = audio
        self.chats = chats
        self.attachments = attachments
        self.engine = engine
        selectDefaultRecipeIfNeeded()
    }

    var selectedRecipe: ModelRecipe? {
        library.recipes.first { $0.id == draft.recipeID }
    }

    var canGenerate: Bool {
        guard !phase.isBusy, let recipe = selectedRecipe else { return false }
        return recipe.canRun(prompt: draft.prompt, hasAttachment: draft.attachment != nil)
    }

    /// The most recent image in the thread.
    var latestImage: GalleryItem? {
        turns.last { $0.image != nil }?.image
    }

    // MARK: - Generating

    /// Sends the draft's prompt: it moves into the thread and the field empties.
    func generate() {
        guard canGenerate, let recipe = selectedRecipe else { return }
        if draft.randomSeed {
            draft.seed = GenerationRequest.randomSeed()
        }
        let request = draft.request(for: recipe)
        let turn = GenerationTurn(
            prompt: request.prompt,
            kind: recipe.outputKind,
            width: request.image?.width,
            height: request.image?.height,
            attachment: draft.attachment
        )
        turns.append(turn)
        draft.prompt = ""
        draft.attachment = nil
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
        draft.attachment = turn.attachment
        generate()
    }

    func cancel() {
        task?.cancel()
    }

    /// Frees the memory held by the loaded model. It loads again on the next prompt.
    func unloadModel() {
        guard !phase.isBusy else { return }
        loadedRecipeID = nil
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
                    // Progress only arrives once the model is in memory.
                    loadedRecipeID = recipe.id
                    phase = .running(progress)
                case .preview(let image):
                    preview = image
                case .finished(let output):
                    let record = GenerationRecord(
                        recipeID: recipe.id,
                        recipeName: recipe.name,
                        request: request,
                        durationSeconds: Date().timeIntervalSince(started)
                    )
                    switch output {
                    case .text(let text): return .text(text)
                    case .image(let image): return .finished(try gallery.add(image, record: record))
                    case .audio(let sound): return .audio(try audio.add(sound, record: record))
                    }
                }
            }
            return .failed("The engine finished without producing an image.")
        } catch is CancellationError {
            return .cancelled
        } catch {
            // A failed run may have taken the helper down with it.
            loadedRecipeID = nil
            return .failed(GenerationFailure.message(for: error, recipe: recipe))
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
        let attachmentName = first.attachment.map(AttachmentLibrary.displayName(of:))
        var chat = chats.chat(id) ?? Chat(id: id, title: Chat.defaultTitle(for: first.prompt, attachmentName: attachmentName))
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
        draft.attachment = nil
    }

    /// Shows a saved chat. Does nothing while an image is generating.
    func open(_ chat: Chat) {
        guard !phase.isBusy, chat.id != chatID else { return }
        chatID = chat.id
        turns = chat.turns.map {
            GenerationTurn($0, images: gallery.items, sounds: audio.items, attachments: attachments)
        }
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
