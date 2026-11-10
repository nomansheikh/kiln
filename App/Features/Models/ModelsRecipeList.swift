import KilnCore
import SwiftUI

/// The scrolling list of recipe cards, with any recipe load problems above it.
struct ModelsRecipeList: View {
    @Environment(AppModel.self) private var model

    let showsDownloadedOnly: Bool

    private var visibleRecipes: [ModelRecipe] {
        let library = model.library
        return showsDownloadedOnly ? library.recipes.filter { library.isInstalled($0) } : library.recipes
    }

    var body: some View {
        let problems = model.library.recipeProblems
        let recipes = visibleRecipes

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
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
                    }
                }
            }
            .frame(maxWidth: Theme.contentWidth)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
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
