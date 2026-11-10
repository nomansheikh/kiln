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

    private(set) var recipes: [ModelRecipe] = []
    private(set) var recipeProblems: [RecipeStore.LoadFailure] = []
    private(set) var installedIDs: Set<String> = []
    private(set) var downloadStatuses: [String: DownloadStatus] = [:]

    /// Called after the set of installed models changes.
    @ObservationIgnored var onInstalledChange: (() -> Void)?

    init(storage: ModelStorage, recipeStore: RecipeStore, hub: HFClient, downloads: DownloadManager) {
        self.storage = storage
        self.recipeStore = recipeStore
        self.hub = hub
        self.downloads = downloads
        reloadRecipes()
        Task { await observeDownloads() }
    }

    // MARK: - Reading

    var installedRecipes: [ModelRecipe] {
        recipes.filter { installedIDs.contains($0.id) }
    }

    /// Recipes with a download queued or in progress.
    var activeDownloads: [(recipe: ModelRecipe, status: DownloadStatus)] {
        recipes.compactMap { recipe in
            guard let status = downloadStatuses[recipe.id], status.isActive else { return nil }
            return (recipe, status)
        }
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
        recipes = result.recipes
        recipeProblems = result.failures
        refreshInstalled()
    }

    /// Adds a recipe from a JSON file the user picked.
    func importRecipe(from file: URL) throws {
        try recipeStore.importRecipe(from: file)
        reloadRecipes()
    }

    /// Turns one file from a Hugging Face repo into a single-file recipe and downloads it.
    func downloadFromHub(_ file: HFFile, in info: HFModelInfo) throws {
        let recipe = ModelRecipe.singleFile(file, in: info)
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
}
