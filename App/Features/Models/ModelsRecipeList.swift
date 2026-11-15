import KilnCore
import SwiftUI

/// The recipe cards section, with any recipe load problems above it.
/// It is laid out inside the Models screen's scroll view.
struct ModelsRecipeList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let showsDownloadedOnly: Bool
    /// Only models for this task are listed. Nil lists every model.
    var task: ModelTask?
    /// Only models whose name contains this text are listed. Empty lists every model.
    var query = ""

    @AppStorage("models.recommendedExpanded") private var recommendedExpanded = true
    @AppStorage("models.catalogExpanded") private var catalogExpanded = false
    @AppStorage("models.addedExpanded") private var addedExpanded = true

    private var visibleRecipes: [ModelRecipe] {
        let library = model.library
        return library.recipes.filter { recipe in
            (task == nil || recipe.task == task) && (!showsDownloadedOnly || library.isInstalled(recipe))
                && (query.isEmpty || matches(recipe))
        }
    }

    /// Whether a recipe's name, id or one of its Hugging Face repos contains the search text.
    /// A pasted link to a repo matches by the repo it names.
    private func matches(_ recipe: ModelRecipe) -> Bool {
        let text = HFClient.repoID(in: query) ?? query
        let files = model.library.variants(of: recipe).flatMap(\.components) + recipe.components
        return recipe.name.localizedCaseInsensitiveContains(text) || recipe.id.localizedCaseInsensitiveContains(text)
            || files.contains { $0.repo.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        let problems = model.library.recipeProblems
        let recipes = visibleRecipes
        let userIDs = model.library.userRecipeIDs
        let catalogIDs = model.library.catalogIDs
        // A search or the Downloaded filter is looking for something specific, so nothing stays folded.
        let showsAll = !query.isEmpty || showsDownloadedOnly

        Group {
            if !problems.isEmpty {
                RecipeProblemsView(problems: problems)
            }
            if recipes.isEmpty {
                // While searching, the Hugging Face results below say when nothing matched.
                if query.isEmpty { emptyState }
            } else {
                section(
                    showsDownloadedOnly ? "Downloaded" : "Recommended",
                    recipes.filter { !userIDs.contains($0.id) && (showsDownloadedOnly || !catalogIDs.contains($0.id)) },
                    isExpanded: showsAll ? .constant(true) : $recommendedExpanded
                )
                if !showsDownloadedOnly {
                    section(
                        "More models",
                        recipes.filter { catalogIDs.contains($0.id) },
                        note: "Listed by the engines' own projects. Kiln has not tested these, so one may not load or may need a setting Kiln does not offer yet.",
                        isExpanded: showsAll ? .constant(true) : $catalogExpanded
                    )
                }
                section("Added by you", recipes.filter { userIDs.contains($0.id) }, isExpanded: showsAll ? .constant(true) : $addedExpanded)
            }
        }
        // Animate on state changes only; byte counts tick far too often to animate.
        .animation(Motion.layout(reduced: reduceMotion), value: model.library.downloadStatuses.mapValues(\.state))
        .animation(Motion.layout(reduced: reduceMotion), value: model.library.installedIDs)
        // A recipe added or removed is animated; a filter or a search is not. Those
        // change dozens of tall cards at once, and animating that inside the lazy
        // list made the cards and the sections below them move at different times.
        .animation(Motion.layout(reduced: reduceMotion), value: model.library.recipes.map(\.id))
        // Collapsing and expanding are instant. Animating them moved the cards
        // and the sections below at different times inside the lazy list.
        .transaction(value: recommendedExpanded) { $0.animation = nil }
        .transaction(value: catalogExpanded) { $0.animation = nil }
        .transaction(value: addedExpanded) { $0.animation = nil }
    }

    /// A titled, collapsible group of recipe cards, or nothing when the group is empty.
    @ViewBuilder
    private func section(_ title: String, _ recipes: [ModelRecipe], note: String? = nil, isExpanded: Binding<Bool>) -> some View {
        if !recipes.isEmpty {
            ModelsSectionTitle(text: title, count: recipes.count, isExpanded: isExpanded)
            if isExpanded.wrappedValue {
                if let note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 2)
                        .padding(.bottom, 2)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(recipes) { recipe in
                        RecipeCard(recipe: recipe)
                            .transition(Motion.rise(reduced: reduceMotion))
                    }
                }
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
