import Foundation

/// The catalogue: models the engines can run that nobody wrote a recipe for.
///
/// `scripts/catalog.py` generates it from what the engines' own projects
/// publish, with every file pinned like a recipe's. Its entries are recipes in
/// form, but untested, so the app lists them apart from the curated ones.
extension RecipeStore {
    /// One catalogue file: where it was generated from and its entries.
    private struct Catalog: Decodable {
        /// An entry that failed to decode is dropped without failing the rest.
        struct Entry: Decodable {
            let recipe: ModelRecipe?

            init(from decoder: Decoder) throws {
                recipe = try? ModelRecipe(from: decoder)
            }
        }

        let recipes: [Entry]
    }

    /// The catalogue's entries, without the models a curated recipe already covers.
    ///
    /// An entry, or one of its variants, is covered when a curated recipe
    /// downloads the same main file. The curated one is kept: it was checked,
    /// and may carry more, such as extra voices.
    func catalogRecipes(notCoveredBy curated: [ModelRecipe]) -> [ModelRecipe] {
        guard let catalogDirectory else { return [] }
        let covered = Set(curated.flatMap(Self.mainFiles))
        var result: [ModelRecipe] = []
        for file in Self.recipeFiles(in: catalogDirectory) {
            guard let data = try? Data(contentsOf: file),
                  let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
            else { continue }
            for var recipe in catalog.recipes.compactMap(\.recipe) {
                if let variants = recipe.variants, !variants.isEmpty {
                    recipe.variants = variants.filter { variant in
                        !variant.components.contains { Self.isMain($0) && covered.contains(Self.key($0)) }
                    }
                    guard recipe.variants?.isEmpty == false else { continue }
                }
                guard !recipe.components.contains(where: { Self.isMain($0) && covered.contains(Self.key($0)) }),
                      (try? recipe.validate()) != nil
                else { continue }
                result.append(recipe)
            }
        }
        return result
    }

    /// The files that are the model itself, in every variant of a recipe.
    private static func mainFiles(of recipe: ModelRecipe) -> [String] {
        (recipe.components + (recipe.variants ?? []).flatMap(\.components)).filter(isMain).map(key)
    }

    private static func isMain(_ component: ModelRecipe.Component) -> Bool {
        [.model, .checkpoint, .diffusionModel].contains(component.role)
    }

    private static func key(_ component: ModelRecipe.Component) -> String {
        component.repo + "\n" + component.file
    }
}
