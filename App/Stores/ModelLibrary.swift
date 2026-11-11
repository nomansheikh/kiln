import Foundation
import KilnCore
import Observation

/// The models Kiln knows about: recipes, what is installed, and downloads.
@MainActor
@Observable
final class ModelLibrary {
    let storage: ModelStorage
    let memory = MemoryFitEstimator()
    let hub: HFClient
    private let recipeStore: RecipeStore
    private let downloads: DownloadManager
    private let variantSelection: VariantSelection
    /// Recipes as written, before a variant is merged in.
    @ObservationIgnored private var sourceRecipes: [String: ModelRecipe] = [:]

    private(set) var recipes: [ModelRecipe] = []
    /// Ids of recipes the user added, as opposed to the ones shipped with the app.
    private(set) var userRecipeIDs: Set<String> = []
    private(set) var recipeProblems: [RecipeStore.LoadFailure] = []
    private(set) var installedIDs: Set<String> = []
    private(set) var downloadStatuses: [String: DownloadStatus] = [:]
    /// Speed and time left for each download that is transferring.
    private(set) var downloadSpeeds: [String: DownloadSpeed] = [:]
    @ObservationIgnored private var rateEstimators: [String: TransferRateEstimator] = [:]
    @ObservationIgnored private var speedsPublishedAt = Date.distantPast

    /// Called after the set of installed models changes.
    @ObservationIgnored var onInstalledChange: (() -> Void)?

    init(storage: ModelStorage, recipeStore: RecipeStore, hub: HFClient, downloads: DownloadManager) {
        self.storage = storage
        self.recipeStore = recipeStore
        self.hub = hub
        self.downloads = downloads
        variantSelection = VariantSelection(storage: storage, memory: memory)
        reloadRecipes()
        Task { await observeDownloads() }
    }

    // MARK: - Reading

    /// Installed models that can generate images. A lone part of a model is left out.
    var installedRecipes: [ModelRecipe] {
        recipes.filter { installedIDs.contains($0.id) && !$0.isIncompleteSingleFile }
    }

    /// The recipe shipped with the app that includes files from this Hugging Face repo, if any.
    func curatedRecipe(forRepo repo: String) -> ModelRecipe? {
        recipes.first { recipe in
            !userRecipeIDs.contains(recipe.id) && recipe.components.contains { $0.repo == repo }
        }
    }

    /// Recipes with a download queued or in progress.
    var activeDownloads: [(recipe: ModelRecipe, status: DownloadStatus)] {
        recipes.compactMap { recipe in
            guard let status = downloadStatuses[recipe.id], status.isActive else { return nil }
            return (recipe, status)
        }
    }

    /// Every recipe with a download to show, including paused, failed and finished ones.
    var downloadEntries: [(recipe: ModelRecipe, status: DownloadStatus)] {
        recipes
            .compactMap { recipe in downloadStatuses[recipe.id].map { (recipe, $0) } }
            .sorted { $0.1.isActive && !$1.1.isActive }
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

    // MARK: - Recipes

    func reloadRecipes() {
        let result = recipeStore.loadAll()
        sourceRecipes = Dictionary(uniqueKeysWithValues: result.recipes.map { ($0.id, $0) })
        recipes = result.recipes.map(variantSelection.resolve)
        userRecipeIDs = result.userRecipeIDs
        recipeProblems = result.failures
        refreshInstalled()
    }

    // MARK: - Variants

    /// Every variant of a recipe as a runnable recipe; empty when it has none.
    func variants(of recipe: ModelRecipe) -> [ModelRecipe] {
        sourceRecipes[recipe.id]?.resolvedVariants ?? []
    }

    /// Switches a recipe to another variant. Ignored while it is downloading.
    func selectVariant(_ variantID: String, for recipe: ModelRecipe) {
        guard downloadStatuses[recipe.id]?.isActive != true else { return }
        variantSelection.choose(variantID, for: recipe.id)
        Task { await downloads.clear(recipe.id) }
        reloadRecipes()
        // A different set of files may or may not be on disk.
        onInstalledChange?()
    }

    /// Adds a recipe from a JSON file the user picked.
    func importRecipe(from file: URL) throws {
        try recipeStore.importRecipe(from: file)
        reloadRecipes()
    }

    /// Turns one file from a Hugging Face repo into a recipe and downloads it: the file
    /// in place of a known model's denoiser when the repo is a version of that model,
    /// otherwise a single-file recipe.
    func downloadFromHub(_ file: HFFile, in info: HFModelInfo) throws {
        let recipe = familyRecipe(for: info)?.adapted(to: file, in: info) ?? ModelRecipe.singleFile(file, in: info)
        try recipeStore.save(recipe)
        reloadRecipes()
        download(recipe)
    }

    /// Deletes the recipe's files from disk. The recipe itself stays in the list.
    func deleteModel(_ recipe: ModelRecipe) throws {
        try storage.delete(recipe, keeping: installedRecipes)
        Task { await downloads.clear(recipe.id) }
        refreshInstalled()
    }

    /// Removes a recipe the user added, with its files unless another recipe uses them.
    func removeRecipe(_ recipe: ModelRecipe) throws {
        guard userRecipeIDs.contains(recipe.id) else { return }
        Task { await downloads.cancel(recipe.id) }
        // Keep files any other recipe lists, installed or not, so they need not be downloaded again.
        try storage.delete(recipe, keeping: recipes)
        try recipeStore.removeUserRecipe(id: recipe.id)
        reloadRecipes()
    }

    // MARK: - Downloads

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

    private func observeDownloads() async {
        for await statuses in await downloads.updates() {
            let finished = statuses.contains { id, status in
                status.state == .completed && downloadStatuses[id]?.state != .completed
            }
            downloadStatuses = statuses
            updateSpeeds(from: statuses)
            if finished {
                refreshInstalled()
            }
        }
    }

    private func updateSpeeds(from statuses: [String: DownloadStatus]) {
        var speeds: [String: DownloadSpeed] = [:]
        for (id, status) in statuses where status.state == .downloading {
            var estimator = rateEstimators[id] ?? TransferRateEstimator()
            estimator.record(bytes: status.receivedBytes)
            rateEstimators[id] = estimator
            if let rate = estimator.bytesPerSecond {
                speeds[id] = DownloadSpeed(
                    bytesPerSecond: rate,
                    secondsRemaining: status.totalBytes.flatMap { estimator.secondsRemaining(until: $0) }
                )
            }
        }
        // A paused or finished transfer starts its estimate afresh next time.
        rateEstimators = rateEstimators.filter { speeds[$0.key] != nil || statuses[$0.key]?.state == .downloading }
        // Progress arrives many times a second; a steadier readout is easier to read.
        let now = Date()
        if Set(speeds.keys) != Set(downloadSpeeds.keys) || now.timeIntervalSince(speedsPublishedAt) >= 1 {
            downloadSpeeds = speeds
            speedsPublishedAt = now
        }
    }

    private func refreshInstalled() {
        let installed = Set(recipes.filter(storage.isInstalled).map(\.id))
        guard installed != installedIDs else { return }
        installedIDs = installed
        onInstalledChange?()
    }

    #if DEBUG
    /// Shows sample downloads for snapshots.
    func loadPreview(statuses: [String: DownloadStatus], speeds: [String: DownloadSpeed]) {
        downloadStatuses = statuses
        downloadSpeeds = speeds
    }
    #endif
}
