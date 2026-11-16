import Foundation

/// What the catalog makes of the files of a Hugging Face repo.
extension ModelCatalog {
    /// What Kiln can do with a repo. `usableBytes` is the memory a model can use on this Mac.
    public func support(forRepo repo: String, info: HFModelInfo?, failed: Bool, usableBytes: Double) -> HubRepoSupport {
        if let recipe = curatedRecipe(forRepo: repo) {
            return .recipe(recipe)
        }
        guard let info else { return failed ? .unavailable : .checking }
        if let base = familyRecipe(for: info) {
            let companions = base.components
                .filter { $0.role != .diffusionModel }
                .reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
            if let file = info.bestDenoiser(usableBytes: usableBytes, companionBytes: companions) {
                return .family(file, info, base: base)
            }
        }
        if let file = info.bestStandaloneCheckpoint(usableBytes: usableBytes) {
            return .checkpoint(file, info)
        }
        return .unsupported
    }

    /// The recipe made for a file when it was downloaded from the Hugging Face list.
    public func recipe(for file: HFFile, in info: HFModelInfo) -> ModelRecipe? {
        recipes.first { recipe in
            recipe.components.contains { $0.repo == info.id && $0.file == file.path }
        }
    }

    /// Whether a file from a Hugging Face repo is already installed or on its way,
    /// judged by the recipe that was made for it when its download started.
    public func availability(of file: HFFile, in info: HFModelInfo) -> HubFileAvailability {
        guard let recipe = recipe(for: file, in: info) else { return .available }
        if isInstalled(recipe) {
            return .installed
        }
        if let status = downloadStatuses[recipe.id], status.isActive {
            return .transferring(status)
        }
        return .available
    }
}
