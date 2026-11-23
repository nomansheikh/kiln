import Foundation

/// What Kiln knows about its models at one moment: the recipes, which are
/// installed and which are downloading. The questions the app asks about them
/// are answered here, where they are tested; `ModelLibrary` keeps one up to date.
public struct ModelCatalog: Sendable, Equatable {
    /// Every recipe, with its chosen variant merged in.
    public var recipes: [ModelRecipe]
    /// Ids of recipes the user added, as opposed to the ones shipped with the app.
    public var userRecipeIDs: Set<String>
    /// Ids of the entries from the catalogue: models an engine can run that have no
    /// recipe written and tested for them.
    public var catalogIDs: Set<String>
    public var installedIDs: Set<String>
    public var downloadStatuses: [String: DownloadStatus]

    public init(
        recipes: [ModelRecipe] = [], userRecipeIDs: Set<String> = [], catalogIDs: Set<String> = [],
        installedIDs: Set<String> = [], downloadStatuses: [String: DownloadStatus] = [:]
    ) {
        self.recipes = recipes
        self.userRecipeIDs = userRecipeIDs
        self.catalogIDs = catalogIDs
        self.installedIDs = installedIDs
        self.downloadStatuses = downloadStatuses
    }

    // MARK: - Installed models

    public func isInstalled(_ recipe: ModelRecipe) -> Bool {
        installedIDs.contains(recipe.id)
    }

    /// Installed models that can be used. A lone part of a model is left out.
    public var installedRecipes: [ModelRecipe] {
        recipes.filter { installedIDs.contains($0.id) && !$0.isIncompleteSingleFile }
    }

    /// Installed models the Generate screen can run. Those that make 3D objects
    /// have a screen of their own.
    public var chatRecipes: [ModelRecipe] {
        installedRecipes.filter { $0.task != .objects }
    }

    /// The model the Generate screen starts with: an image model if one is installed.
    public var defaultRecipe: ModelRecipe? {
        let installed = chatRecipes
        return installed.first { $0.outputKind == .image } ?? installed.first
    }

    // MARK: - Recipes shipped with the app

    private func isCurated(_ recipe: ModelRecipe) -> Bool {
        !userRecipeIDs.contains(recipe.id) && !catalogIDs.contains(recipe.id)
    }

    /// The recipe shipped with the app that includes files from this Hugging Face repo, if any.
    public func curatedRecipe(forRepo repo: String) -> ModelRecipe? {
        recipes.first { recipe in isCurated(recipe) && recipe.components.contains { $0.repo == repo } }
    }

    /// The recipe shipped with the app for the model this repo is a version of, if any.
    public func familyRecipe(for info: HFModelInfo) -> ModelRecipe? {
        recipes.first { isCurated($0) && $0.isSameFamily(as: info) }
    }

    // MARK: - Downloads

    /// Recipes with a download queued or in progress.
    public var activeDownloads: [(recipe: ModelRecipe, status: DownloadStatus)] {
        recipes.compactMap { recipe in
            guard let status = downloadStatuses[recipe.id], status.isActive else { return nil }
            return (recipe, status)
        }
    }

    /// Every recipe with a download to show, including paused, failed and finished ones.
    public var downloadEntries: [(recipe: ModelRecipe, status: DownloadStatus)] {
        recipes
            .compactMap { recipe in downloadStatuses[recipe.id].map { (recipe, $0) } }
            .sorted { $0.1.isActive && !$1.1.isActive }
    }

    // MARK: - The Models list

    /// The recipes the Models screen lists: those of a task, those downloaded,
    /// and those a search matches. `variants` gives every variant of a recipe, so
    /// that a repo only another variant uses is found too.
    public func listed(
        task: ModelTask? = nil, downloadedOnly: Bool = false, query: String = "",
        variants: (ModelRecipe) -> [ModelRecipe] = { _ in [] }
    ) -> [ModelRecipe] {
        // A pasted link to a repo matches by the repo it names.
        let text = HFClient.repoID(in: query) ?? query
        return recipes.filter { recipe in
            guard task == nil || recipe.task == task, !downloadedOnly || isInstalled(recipe) else { return false }
            guard !query.isEmpty else { return true }
            let files = variants(recipe).flatMap(\.components) + recipe.components
            return recipe.name.localizedCaseInsensitiveContains(text) || recipe.id.localizedCaseInsensitiveContains(text)
                || files.contains { $0.repo.localizedCaseInsensitiveContains(text) }
        }
    }
}
