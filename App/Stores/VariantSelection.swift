import Foundation
import KilnCore

/// Decides which variant of a recipe the app works with, and remembers the
/// user's choice.
struct VariantSelection {
    let storage: ModelStorage
    let memory: MemoryFitEstimator
    var defaults: UserDefaults = .standard

    private func key(_ recipeID: String) -> String {
        "variant.\(recipeID)"
    }

    /// The recipe with one variant's files merged in. Order of preference: the
    /// user's pick, a variant that is already installed, then the best fit for this Mac.
    /// A recipe without variants is returned as it is.
    func resolve(_ recipe: ModelRecipe) -> ModelRecipe {
        guard recipe.hasVariants else { return recipe }
        let candidates = recipe.resolvedVariants
        if let chosen = defaults.string(forKey: key(recipe.id)),
           let match = candidates.first(where: { $0.selectedVariantID == chosen }) {
            return match
        }
        return candidates.first(where: storage.isInstalled) ?? memory.bestVariant(of: recipe) ?? recipe
    }

    func choose(_ variantID: String, for recipeID: String) {
        defaults.set(variantID, forKey: key(recipeID))
    }
}
