import Foundation
import KilnCore

/// The models the 3D screen works with: the one that makes objects, and the
/// image model that draws a picture from a description.
extension ObjectsStore {
    /// Installed models that make 3D objects.
    var recipes: [ModelRecipe] {
        library.installedRecipes.filter { $0.task == .objects }
    }

    var selectedRecipe: ModelRecipe? {
        recipes.first { $0.id == draft.recipeID }
    }

    func selectRecipe(_ recipe: ModelRecipe?) {
        draft.select(recipe)
    }

    /// Picks an installed model when the current choice is missing or was deleted.
    func selectDefaultRecipeIfNeeded() {
        if selectedRecipe != nil { return }
        selectRecipe(recipes.first)
    }

    /// Installed models that draw images, for making a picture from a description.
    var pictureRecipes: [ModelRecipe] {
        library.installedRecipes.filter { $0.task == .images && $0.defaults != nil }
    }

    var pictureRecipe: ModelRecipe? {
        pictureRecipes.first { $0.id == pictureRecipeID } ?? pictureRecipes.first
    }
}
