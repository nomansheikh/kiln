import KilnCore
import SwiftUI

/// The recipe cards section, with any recipe load problems above it.
/// It is laid out inside the Models screen's scroll view.
struct ModelsRecipeList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let showsDownloadedOnly: Bool

    @AppStorage("models.recommendedExpanded") private var recommendedExpanded = true
    @AppStorage("models.addedExpanded") private var addedExpanded = true

    private var visibleRecipes: [ModelRecipe] {
        let library = model.library
        return showsDownloadedOnly ? library.recipes.filter { library.isInstalled($0) } : library.recipes
    }

    var body: some View {
        let problems = model.library.recipeProblems
        let recipes = visibleRecipes
        let userIDs = model.library.userRecipeIDs

        Group {
            if !problems.isEmpty {
                RecipeProblemsView(problems: problems)
            }
            if recipes.isEmpty {
                emptyState
            } else {
                section(
                    showsDownloadedOnly ? "Downloaded" : "Recommended",
                    recipes.filter { !userIDs.contains($0.id) },
                    isExpanded: $recommendedExpanded
                )
                section("Added by you", recipes.filter { userIDs.contains($0.id) }, isExpanded: $addedExpanded)
            }
        }
        // Animate on state changes only; byte counts tick far too often to animate.
        .animation(Motion.layout(reduced: reduceMotion), value: model.library.downloadStatuses.mapValues(\.state))
        .animation(Motion.layout(reduced: reduceMotion), value: model.library.installedIDs)
        .animation(Motion.layout(reduced: reduceMotion), value: recipes.map(\.id))
        // Collapsing fades the whole group at once. Moving each card separately
        // made them slide over one another while the list closed up.
        .animation(.easeOut(duration: 0.18), value: recommendedExpanded)
        .animation(.easeOut(duration: 0.18), value: addedExpanded)
    }

    /// A titled, collapsible group of recipe cards, or nothing when the group is empty.
    @ViewBuilder
    private func section(_ title: String, _ recipes: [ModelRecipe], isExpanded: Binding<Bool>) -> some View {
        if !recipes.isEmpty {
            ModelsSectionTitle(text: title, count: recipes.count, isExpanded: isExpanded)
            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(recipes) { recipe in
                        RecipeCard(recipe: recipe)
                            .transition(Motion.rise(reduced: reduceMotion))
                    }
                }
                .transition(.opacity)
            }
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
