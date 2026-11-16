/// What Kiln can do with a Hugging Face repo, reduced to one answer for the user.
public enum HubRepoSupport: Sendable, Equatable {
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
