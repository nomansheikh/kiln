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
    /// Ids of the entries from the catalogue: models an engine can run that have no
    /// recipe written and tested for them.
    private(set) var catalogIDs: Set<String> = []
    private(set) var recipeProblems: [RecipeStore.LoadFailure] = []
    private(set) var installedIDs: Set<String> = []
    private(set) var downloadStatuses: [String: DownloadStatus] = [:]
    /// Speed and time left for each download that is transferring.
    private(set) var downloadSpeeds: [String: DownloadSpeed] = [:]
    @ObservationIgnored private var speedTracker = DownloadSpeedTracker()

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

    /// The library at this moment, as the value that answers questions about it.
    /// The rules are KilnCore's, where they are tested.
    var catalog: ModelCatalog {
        ModelCatalog(
            recipes: recipes, userRecipeIDs: userRecipeIDs, catalogIDs: catalogIDs,
            installedIDs: installedIDs, downloadStatuses: downloadStatuses
        )
    }

    /// Installed models that can be used. A lone part of a model is left out.
    var installedRecipes: [ModelRecipe] { catalog.installedRecipes }

    /// Recipes with a download queued or in progress.
    var activeDownloads: [(recipe: ModelRecipe, status: DownloadStatus)] { catalog.activeDownloads }

    /// Every recipe with a download to show, including paused, failed and finished ones.
    var downloadEntries: [(recipe: ModelRecipe, status: DownloadStatus)] { catalog.downloadEntries }

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
        catalogIDs = result.catalogIDs
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
        let recipe = catalog.familyRecipe(for: info)?.adapted(to: file, in: info) ?? ModelRecipe.singleFile(file, in: info)
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
            speedTracker.update(from: statuses)
            // The tracker holds its readout steady, so views are told only when it changes.
            if speedTracker.speeds != downloadSpeeds {
                downloadSpeeds = speedTracker.speeds
            }
            if finished {
                refreshInstalled()
            }
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
