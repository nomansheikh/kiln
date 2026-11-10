import Foundation
import Testing
@testable import KilnCore

@Suite struct RecipeStoreTests {
    let root: URL
    let store: RecipeStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-tests-\(UUID().uuidString)")
        store = RecipeStore(
            bundledDirectory: root.appendingPathComponent("bundled"),
            userDirectory: root.appendingPathComponent("user")
        )
        try FileManager.default.createDirectory(at: store.bundledDirectory, withIntermediateDirectories: true)
    }

    private func write(_ recipe: ModelRecipe, to directory: URL, as name: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name ?? "\(recipe.id).json")
        try JSONEncoder().encode(recipe).write(to: file)
        return file
    }

    @Test func loadsBundledAndUserRecipes() throws {
        _ = try write(makeRecipe(id: "bundled-one"), to: store.bundledDirectory)
        _ = try write(makeRecipe(id: "user-one"), to: store.userDirectory)

        let result = store.loadAll()

        #expect(result.recipes.map(\.id) == ["bundled-one", "user-one"])
        #expect(result.failures.isEmpty)
    }

    @Test func missingUserDirectoryIsNotAnError() throws {
        _ = try write(makeRecipe(id: "bundled-one"), to: store.bundledDirectory)

        let result = store.loadAll()

        #expect(result.recipes.count == 1)
        #expect(result.failures.isEmpty)
    }

    @Test func reportsBrokenFilesWithoutDroppingGoodOnes() throws {
        _ = try write(makeRecipe(id: "good"), to: store.bundledDirectory)
        try Data("{ not json".utf8).write(to: store.bundledDirectory.appendingPathComponent("broken.json"))
        try Data(#"{"id": "partial"}"#.utf8).write(to: store.bundledDirectory.appendingPathComponent("partial.json"))

        let result = store.loadAll()

        #expect(result.recipes.map(\.id) == ["good"])
        #expect(result.failures.map(\.file.lastPathComponent) == ["broken.json", "partial.json"])
        #expect(result.failures[0].message == "The file is not valid JSON.")
        #expect(result.failures[1].message == "Missing field \"name\".")
    }

    @Test func bundledRecipeWinsOverUserRecipeWithSameID() throws {
        _ = try write(makeRecipe(id: "same", minMemoryGB: 8), to: store.bundledDirectory)
        _ = try write(makeRecipe(id: "same", minMemoryGB: 99), to: store.userDirectory)

        let result = store.loadAll()

        #expect(result.recipes.map(\.minMemoryGB) == [8])
        #expect(result.failures.count == 1)
    }

    @Test func importCopiesAValidRecipeIntoTheUserDirectory() throws {
        let source = try write(makeRecipe(id: "imported"), to: root.appendingPathComponent("elsewhere"), as: "whatever.json")

        let recipe = try store.importRecipe(from: source)

        #expect(recipe.id == "imported")
        #expect(FileManager.default.fileExists(atPath: store.userDirectory.appendingPathComponent("imported.json").path))
        #expect(store.loadAll().recipes.map(\.id) == ["imported"])
    }

    @Test func importRejectsInvalidRecipes() throws {
        let source = try write(makeRecipe(components: []), to: root.appendingPathComponent("elsewhere"))

        #expect(throws: RecipeValidationError.noComponents) { try store.importRecipe(from: source) }
        #expect(store.loadAll().recipes.isEmpty)
    }

    @Test func importRejectsAnIDUsedByABundledRecipe() throws {
        _ = try write(makeRecipe(id: "taken"), to: store.bundledDirectory)
        let source = try write(makeRecipe(id: "taken"), to: root.appendingPathComponent("elsewhere"))

        #expect(throws: RecipeStore.ImportError.idTaken("taken")) { try store.importRecipe(from: source) }
    }
}
