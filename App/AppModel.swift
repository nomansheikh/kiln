import AppKit
import KilnCore
import Observation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case generate, models, gallery, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generate: "Generate"
        case .models: "Models"
        case .gallery: "Gallery"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .generate: "wand.and.stars"
        case .models: "shippingbox"
        case .gallery: "photo.on.rectangle.angled"
        case .settings: "gearshape"
        }
    }
}

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
}

enum GenerationPhase: Equatable {
    case idle
    case starting
    case loadingModel
    case running(GenerationProgress)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .starting, .loadingModel, .running: true
        case .idle, .failed: false
        }
    }
}

/// The app's single source of state. Views read it and call its methods.
@MainActor
@Observable
final class AppModel {
    // MARK: Services

    let storage = ModelStorage(root: ModelStorage.defaultRoot)
    let gallery = GalleryStore(directory: GalleryStore.defaultDirectory)
    let memory = MemoryFitEstimator()
    let recipeStore: RecipeStore
    let tokenStore: any TokenStore = KeychainTokenStore()
    let hub: HFClient
    private let downloads: DownloadManager
    private let engine: any InferenceEngine

    // MARK: State

    var selection: SidebarItem? = .generate

    private(set) var recipes: [ModelRecipe] = []
    private(set) var recipeProblems: [RecipeStore.LoadFailure] = []
    private(set) var installedIDs: Set<String> = []
    private(set) var downloadStatuses: [String: DownloadStatus] = [:]

    var draft = GenerationDraft()
    private(set) var phase: GenerationPhase = .idle
    private(set) var latestImage: GalleryItem?
    private var generationTask: Task<Void, Never>?

    private(set) var galleryItems: [GalleryItem] = []
    private(set) var hasToken = false

    /// Samplers offered in the Advanced section, as named by stable-diffusion.cpp.
    static let samplers = [
        "euler", "euler_a", "heun", "dpm2", "dpm++2s_a", "dpm++2m", "dpm++2mv2",
        "ipndm", "ipndm_v", "lcm", "ddim_trailing", "tcd",
    ]

    init() {
        let tokenStore = self.tokenStore
        let support = URL.applicationSupportDirectory.appendingPathComponent("Kiln", isDirectory: true)
        recipeStore = RecipeStore(
            bundledDirectory: Bundle.main.resourceURL?.appendingPathComponent("recipes") ?? support.appendingPathComponent("bundled"),
            userDirectory: support.appendingPathComponent("recipes", isDirectory: true)
        )
        hub = HFClient(token: { tokenStore.read() })
        downloads = DownloadManager(
            storage: storage,
            downloader: FileDownloader { url in HFClient.authorizationHeader(for: url, token: tokenStore.read()) }
        )
        engine = StableDiffusionCppEngine(
            helperURL: Bundle.main.url(forAuxiliaryExecutable: "kiln-engine")
                ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/kiln-engine"),
            storage: storage
        )
        hasToken = tokenStore.read() != nil

        reloadRecipes()
        reloadGallery()
        Task { await observeDownloads() }
    }

    // MARK: - Models

    var installedRecipes: [ModelRecipe] {
        recipes.filter { installedIDs.contains($0.id) }
    }

    func isInstalled(_ recipe: ModelRecipe) -> Bool {
        installedIDs.contains(recipe.id)
    }

    func downloadStatus(for recipe: ModelRecipe) -> DownloadStatus? {
        downloadStatuses[recipe.id]
    }

    func fit(for recipe: ModelRecipe) -> MemoryFit? {
        memory.fit(for: recipe)
    }

    func reloadRecipes() {
        let result = recipeStore.loadAll()
        recipes = result.recipes
        recipeProblems = result.failures
        refreshInstalled()
    }

    func download(_ recipe: ModelRecipe) {
        Task { await downloads.start(recipe) }
    }

    func pauseDownload(_ recipe: ModelRecipe) {
        Task { await downloads.pause(recipe.id) }
    }

    func cancelDownload(_ recipe: ModelRecipe) {
        Task { await downloads.cancel(recipe.id) }
    }

    func dismissDownload(_ recipe: ModelRecipe) {
        Task { await downloads.clear(recipe.id) }
    }

    /// Deletes the recipe's files from disk. The recipe itself stays in the list.
    func deleteModel(_ recipe: ModelRecipe) throws {
        try storage.delete(recipe, keeping: installedRecipes)
        Task { await downloads.clear(recipe.id) }
        refreshInstalled()
    }

    /// Adds a recipe from a JSON file the user picked.
    func importRecipe(from file: URL) throws {
        try recipeStore.importRecipe(from: file)
        reloadRecipes()
    }

    /// Turns one file from a Hugging Face repo into a single-file recipe and downloads it.
    /// Only all-in-one checkpoints run this way; multi-part models need a curated recipe.
    func downloadFromHub(_ file: HFFile, in info: HFModelInfo) throws {
        let slug = "\(info.id)-\(file.name)".lowercased().map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-") ? character : "-"
        }
        let isXL = file.name.lowercased().contains("xl")
        let recipe = ModelRecipe(
            id: String(slug).trimmingCharacters(in: CharacterSet(charactersIn: ".-")),
            name: file.name,
            engine: StableDiffusionCppEngine.engineID,
            components: [
                .init(role: .checkpoint, repo: info.id, file: file.path, revision: info.revision,
                      sizeBytes: file.sizeBytes, sha256: file.sha256),
            ],
            defaults: .init(steps: 20, cfg: 7.0, sampler: "euler", width: isXL ? 1024 : 512, height: isXL ? 1024 : 512),
            licenseNote: info.license.map { "License: \($0). See the model page on Hugging Face." }
        )
        try recipe.validate()
        let directory = recipeStore.userDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(recipe).write(to: directory.appendingPathComponent("\(recipe.id).json"), options: .atomic)
        reloadRecipes()
        download(recipe)
    }

    private func refreshInstalled() {
        installedIDs = Set(recipes.filter(storage.isInstalled).map(\.id))
        if draft.recipeID == nil || !installedIDs.contains(draft.recipeID ?? "") {
            selectRecipe(installedRecipes.first)
        }
    }

    private func observeDownloads() async {
        for await statuses in await downloads.updates() {
            let finished = statuses.contains { id, status in
                status.state == .completed && downloadStatuses[id]?.state != .completed
            }
            downloadStatuses = statuses
            if finished {
                refreshInstalled()
            }
        }
    }

    // MARK: - Generate

    var selectedRecipe: ModelRecipe? {
        recipes.first { $0.id == draft.recipeID }
    }

    var canGenerate: Bool {
        !phase.isBusy && selectedRecipe != nil
            && !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Selects a model and applies its recommended settings.
    func selectRecipe(_ recipe: ModelRecipe?) {
        draft.recipeID = recipe?.id
        guard let defaults = recipe?.defaults else { return }
        draft.width = defaults.width
        draft.height = defaults.height
        draft.steps = defaults.steps
        draft.cfg = defaults.cfg
        draft.sampler = defaults.sampler
    }

    func generate() {
        guard canGenerate, let recipe = selectedRecipe else { return }
        if draft.randomSeed {
            draft.seed = GenerationRequest.randomSeed()
        }
        // The recipe's sigma schedule only fits its own step count.
        let sigmas = draft.steps == recipe.defaults.steps ? recipe.defaults.sigmas : nil
        let request = GenerationRequest(
            prompt: draft.prompt,
            negativePrompt: draft.negativePrompt,
            width: draft.width,
            height: draft.height,
            steps: draft.steps,
            cfg: draft.cfg,
            sampler: draft.sampler,
            sigmas: sigmas,
            seed: draft.seed
        )

        phase = .starting
        let started = Date()
        generationTask = Task {
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
                        latestImage = try gallery.save(image, record: record)
                        reloadGallery()
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

    /// Clears the canvas and the prompt, ready for a fresh image.
    func newImage() {
        guard !phase.isBusy else {
            selection = .generate
            return
        }
        latestImage = nil
        draft.prompt = ""
        dismissError()
        selection = .generate
    }

    /// Shows a past image on the Generate canvas.
    func show(_ item: GalleryItem) {
        latestImage = item
        selection = .generate
    }

    func cancelGeneration() {
        generationTask?.cancel()
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

    /// Loads a past image's settings into the Generate screen.
    func reuseSettings(of item: GalleryItem) {
        let request = item.record.request
        if recipes.contains(where: { $0.id == item.record.recipeID }) {
            draft.recipeID = item.record.recipeID
        }
        draft.prompt = request.prompt
        draft.negativePrompt = request.negativePrompt
        draft.width = request.width
        draft.height = request.height
        draft.steps = request.steps
        draft.cfg = request.cfg
        draft.sampler = request.sampler
        draft.randomSeed = false
        draft.seed = request.seed
        selection = .generate
    }

    // MARK: - Gallery

    func reloadGallery() {
        galleryItems = gallery.items()
    }

    func deleteGalleryItem(_ item: GalleryItem) throws {
        try gallery.delete(item)
        if latestImage?.id == item.id {
            latestImage = nil
        }
        reloadGallery()
    }

    func copyToPasteboard(_ item: GalleryItem) {
        guard let image = NSImage(contentsOf: item.url) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    func revealInFinder(_ item: GalleryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: - Settings

    func saveToken(_ token: String) throws {
        try tokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
        hasToken = true
    }

    func removeToken() throws {
        try tokenStore.delete()
        hasToken = false
    }

    /// Asks Hugging Face who the saved token belongs to.
    func verifyToken() async throws -> String {
        try await hub.whoAmI()
    }
}
