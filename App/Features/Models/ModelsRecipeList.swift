import KilnCore
import SwiftUI

/// The recipe cards section, with any recipe load problems above it.
/// It is laid out inside the Models screen's scroll view.
struct ModelsRecipeList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let showsDownloadedOnly: Bool

    private var visibleRecipes: [ModelRecipe] {
        let library = model.library
        return showsDownloadedOnly ? library.recipes.filter { library.isInstalled($0) } : library.recipes
    }

    var body: some View {
        let problems = model.library.recipeProblems
        let recipes = visibleRecipes

        Group {
            if !problems.isEmpty {
                RecipeProblemsView(problems: problems)
            }
            if recipes.isEmpty {
                emptyState
            } else {
                ModelsSectionTitle(
                    text: showsDownloadedOnly ? "Downloaded" : "Recommended",
                    count: recipes.count
                )
                ForEach(recipes) { recipe in
                    RecipeCard(recipe: recipe)
                        .transition(Motion.rise(reduced: reduceMotion))
                }
            }
        }
        // Animate on state changes only; byte counts tick far too often to animate.
        .animation(Motion.layout(reduced: reduceMotion), value: model.library.downloadStatuses.mapValues(\.state))
        .animation(Motion.layout(reduced: reduceMotion), value: model.library.installedIDs)
        .animation(Motion.layout(reduced: reduceMotion), value: recipes.map(\.id))
    }

    @ViewBuilder
    private var emptyState: some View {
        if showsDownloadedOnly {
            ContentUnavailableView(
                "No Downloaded Models",
                systemImage: "arrow.down.circle",
                description: Text("Turn off the Downloaded filter to see models you can get.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            ContentUnavailableView(
                "No Recipes",
                systemImage: "shippingbox",
                description: Text("Import a recipe, or search Hugging Face for a checkpoint.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }
}
