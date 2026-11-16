import Foundation
import KilnCore
import Testing

/// The model library: what is installed, downloading, deleting and adding recipes.
@MainActor
@Suite struct ModelLibraryTests {
    @Test func itListsTheRecipesAndWhichAreOnDisk() throws {
        let fixture = try StoreFixture(installed: [StoreFixture.voice])
        #expect(fixture.library.recipes.map(\.id) == ["copier", "picture", "voice", "writer"])
        #expect(fixture.library.installedIDs == ["voice"])
        #expect(fixture.library.installedRecipes.map(\.id) == ["voice"])
        #expect(fixture.library.recipeProblems.isEmpty)
    }

    @Test func aFinishedDownloadInstallsTheModelAndTellsTheScreens() async throws {
        let fixture = try StoreFixture(installed: [])
        var changes = 0
        fixture.library.onInstalledChange = { changes += 1 }

        fixture.library.download(StoreFixture.image)
        try await waitUntil("the model is installed") { fixture.library.isInstalled(StoreFixture.image) }

        #expect(changes == 1)
        #expect(fixture.library.downloadStatus(for: StoreFixture.image)?.state == .completed)
        #expect(fixture.library.downloadEntries.map(\.recipe.id) == ["picture"])
        #expect(fixture.library.activeDownloads.isEmpty)

        fixture.library.dismissDownload(StoreFixture.image)
        try await waitUntil("the entry is gone") { fixture.library.downloadEntries.isEmpty }
    }

    @Test func aScreenFallsBackWhenItsModelIsDeleted() throws {
        let fixture = try StoreFixture()
        let generation = fixture.generationStore()
        let speech = fixture.speechStore()
        // As `AppModel` wires them.
        fixture.library.onInstalledChange = {
            generation.selectDefaultRecipeIfNeeded()
            speech.selectDefaultRecipeIfNeeded()
        }
        #expect(generation.selectedRecipe?.id == "picture")

        try fixture.library.deleteModel(StoreFixture.image)
        #expect(!fixture.library.isInstalled(StoreFixture.image))
        #expect(generation.selectedRecipe?.id == "copier")

        try fixture.library.deleteModel(StoreFixture.copier)
        #expect(speech.selectedRecipe?.id == "voice")
        // The recipe stays in the list, ready to be downloaded again.
        #expect(fixture.library.recipes.count == 4)
    }

    @Test func aRecipeTheUserAddsCanBeRemovedAgainWithItsFiles() throws {
        let fixture = try StoreFixture()
        var mine = StoreFixture.voice
        mine.id = "mine"
        mine.name = "Mine"
        mine.components[0].file = "mine.gguf"
        let file = fixture.root.appendingPathComponent("mine.json")
        try JSONEncoder().encode(mine).write(to: file)

        try fixture.library.importPickedRecipe(.success(file))
        #expect(fixture.library.userRecipeIDs == ["mine"])
        #expect(fixture.library.recipes.contains { $0.id == "mine" })

        // A recipe shipped with the app cannot be removed this way.
        try fixture.library.removeRecipe(StoreFixture.voice)
        #expect(fixture.library.recipes.count == 5)

        try fixture.library.removeRecipe(mine)
        #expect(fixture.library.userRecipeIDs.isEmpty)
        #expect(fixture.library.recipes.count == 4)
    }

    @Test func aRecipeFileThatReusesABuiltInIdIsRefused() throws {
        let fixture = try StoreFixture()
        let file = fixture.root.appendingPathComponent("voice.json")
        try JSONEncoder().encode(StoreFixture.voice).write(to: file)

        #expect(throws: RecipeStore.ImportError.idTaken("voice")) {
            try fixture.library.importPickedRecipe(.success(file))
        }
        #expect(throws: CocoaError.self) {
            try fixture.library.importPickedRecipe(.failure(CocoaError(.userCancelled)))
        }
    }

    @Test func anotherVariantOfAModelCanBeChosen() throws {
        let id = "variants-\(UUID().uuidString.lowercased())"
        defer { UserDefaults.standard.removeObject(forKey: "variant.\(id)") }
        var recipe = StoreFixture.voice
        recipe.id = id
        recipe.components = []
        recipe.variants = ["big", "small"].map {
            .init(id: $0, name: $0.capitalized, components: [
                .init(role: .model, repo: "owner/\(id)", file: "\($0).gguf", revision: "abc", sizeBytes: 7, sha256: StoreFixture.checksum),
            ])
        }
        let fixture = try StoreFixture(recipes: [recipe], installed: [])
        let listed = try #require(fixture.library.recipes.first)
        #expect(fixture.library.variants(of: listed).compactMap(\.selectedVariantID) == ["big", "small"])
        let other = listed.selectedVariantID == "big" ? "small" : "big"

        fixture.library.selectVariant(other, for: listed)

        #expect(fixture.library.recipes.first?.selectedVariantID == other)
        #expect(fixture.library.recipes.first?.components.map(\.file) == ["\(other).gguf"])
    }
}
