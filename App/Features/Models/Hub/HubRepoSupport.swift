import KilnCore

/// What Kiln can do with a Hugging Face repo, reduced to one answer for the user.
enum HubRepoSupport {
    /// A recipe shipped with Kiln covers this model.
    case recipe(ModelRecipe)
    /// The repo's file list is still loading.
    case checking
    /// The repo has a whole model in one file that can be downloaded and run.
    case checkpoint(HFFile, HFModelInfo)
    /// The repo holds the denoiser of a model Kiln has a recipe for. The file runs
    /// with that recipe's other files and settings.
    case family(HFFile, HFModelInfo, base: ModelRecipe)
    /// The model comes in several parts and there is no recipe for it.
    case unsupported
    /// The file list could not be loaded, for example a gated repo without a token.
    case unavailable
}

extension ModelLibrary {
    func support(forRepo repo: String, info: HFModelInfo?, failed: Bool) -> HubRepoSupport {
        if let recipe = curatedRecipe(forRepo: repo) {
            return .recipe(recipe)
        }
        guard let info else { return failed ? .unavailable : .checking }
        if let base = familyRecipe(for: info) {
            let companions = base.components
                .filter { $0.role != .diffusionModel }
                .reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
            if let file = info.bestDenoiser(usableBytes: memory.usableBytes, companionBytes: companions) {
                return .family(file, info, base: base)
            }
        }
        if let file = info.bestStandaloneCheckpoint(usableBytes: memory.usableBytes) {
            return .checkpoint(file, info)
        }
        return .unsupported
    }

    /// The recipe shipped with the app for the model this repo is a version of, if any.
    func familyRecipe(for info: HFModelInfo) -> ModelRecipe? {
        recipes.first { !userRecipeIDs.contains($0.id) && $0.isSameFamily(as: info) }
    }

    /// The recipe made for a file when it was downloaded from the Hugging Face list.
    func recipe(for file: HFFile, in info: HFModelInfo) -> ModelRecipe? {
        recipes.first { recipe in
            recipe.components.contains { $0.repo == info.id && $0.file == file.path }
        }
    }
}
