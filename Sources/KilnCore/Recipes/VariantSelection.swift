import Foundation

/// Decides which variant of a recipe the app works with, and remembers the
/// user's choice.
public struct VariantSelection {
    public let storage: ModelStorage
    public let memory: MemoryFitEstimator
    public var defaults: UserDefaults

    public init(storage: ModelStorage, memory: MemoryFitEstimator, defaults: UserDefaults = .standard) {
        self.storage = storage
        self.memory = memory
        self.defaults = defaults
    }

    private func key(_ recipeID: String) -> String {
        "variant.\(recipeID)"
    }

    /// The recipe with one variant's files merged in. Order of preference: the
    /// user's pick, a variant that is already installed, then the best fit for this Mac.
    /// A recipe without variants is returned as it is.
    public func resolve(_ recipe: ModelRecipe) -> ModelRecipe {
        guard recipe.hasVariants else { return recipe }
        let candidates = recipe.resolvedVariants
        if let chosen = defaults.string(forKey: key(recipe.id)),
           let match = candidates.first(where: { $0.selectedVariantID == chosen }) {
            return match
        }
        return candidates.first(where: storage.isInstalled) ?? memory.bestVariant(of: recipe) ?? recipe
    }

    public func choose(_ variantID: String, for recipeID: String) {
        defaults.set(variantID, forKey: key(recipeID))
    }
}
