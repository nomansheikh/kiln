import Foundation
import Testing
@testable import KilnCore

@Suite struct RecipeCatalogTests {
    let root: URL
    let cache: URL
    let transport = RoutedTransport()
    let base = "https://example.test/recipes"

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-catalog-\(UUID().uuidString)")
        cache = root.appendingPathComponent("recipes-remote")
    }

    private var catalog: RecipeCatalog {
        RecipeCatalog(indexURL: URL(string: "\(base)/index.json")!, cacheDirectory: cache, transport: transport)
    }

    private func publish(_ recipe: ModelRecipe, as name: String? = nil) throws {
        transport.route("\(base)/\(name ?? "\(recipe.id).json")", body: try JSONEncoder().encode(recipe))
    }

    private func publishIndex(_ names: [String], version: Int = 1) {
        let list = names.map { "\"\($0)\"" }.joined(separator: ", ")
        transport.route("\(base)/index.json", body: "{\"version\": \(version), \"recipes\": [\(list)]}")
    }

    private var cachedNames: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []).sorted()
    }

    @Test func fetchesTheListedRecipesIntoTheCache() async throws {
        try publish(makeRecipe(id: "alpha"))
        try publish(makeRecipe(id: "beta"))
        publishIndex(["alpha.json", "beta.json"])

        let count = try await catalog.refresh()

        #expect(count == 2)
        #expect(cachedNames == ["alpha.json", "beta.json"])
    }

    @Test func fetchedRecipesReplaceBundledOnesWithTheSameID() async throws {
        let bundled = root.appendingPathComponent("bundled")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try JSONEncoder().encode(makeRecipe(id: "alpha", minMemoryGB: 8)).write(to: bundled.appendingPathComponent("alpha.json"))
        try JSONEncoder().encode(makeRecipe(id: "only-bundled")).write(to: bundled.appendingPathComponent("only-bundled.json"))
        try publish(makeRecipe(id: "alpha", minMemoryGB: 16))
        try publish(makeRecipe(id: "new-model"))
        publishIndex(["alpha.json", "new-model.json"])
        try await catalog.refresh()

        let store = RecipeStore(bundledDirectory: bundled, userDirectory: root.appendingPathComponent("user"), remoteDirectory: cache)
        let result = store.loadAll()

        #expect(result.recipes.map(\.id) == ["alpha", "new-model", "only-bundled"])
        #expect(result.recipes.first { $0.id == "alpha" }?.minMemoryGB == 16)
        #expect(result.failures.isEmpty)
        #expect(result.userRecipeIDs.isEmpty)
    }

    @Test func skipsRecipesThisVersionCannotUse() async throws {
        try publish(makeRecipe(id: "good"))
        transport.route("\(base)/from-the-future.json", body: #"{"id": "from-the-future", "components": [{"role": "hologram"}]}"#)
        try publish(makeRecipe(id: "other-id"), as: "misnamed.json")
        publishIndex(["good.json", "from-the-future.json", "misnamed.json", "missing.json"])

        let count = try await catalog.refresh()

        #expect(count == 1)
        #expect(cachedNames == ["good.json"])
    }

    @Test func ignoresNamesThatAreNotPlainRecipeFiles() async throws {
        try publish(makeRecipe(id: "good"))
        publishIndex(["good.json", "../escape.json", "nested/x.json", "index.json", "schema.json", "notes.txt", ".hidden.json"])

        try await catalog.refresh()

        #expect(cachedNames == ["good.json"])
        #expect(transport.requestedURLs.sorted() == ["\(base)/good.json", "\(base)/index.json"])
    }

    @Test func aRefreshReplacesTheWholeCache() async throws {
        try publish(makeRecipe(id: "old"))
        publishIndex(["old.json"])
        try await catalog.refresh()

        try publish(makeRecipe(id: "new"))
        publishIndex(["new.json"])
        try await catalog.refresh()

        #expect(cachedNames == ["new.json"])
    }

    @Test func aFailedIndexLeavesTheCacheAsItWas() async throws {
        try publish(makeRecipe(id: "kept"))
        publishIndex(["kept.json"])
        try await catalog.refresh()

        transport.route("\(base)/index.json", status: 500, body: "")
        await #expect(throws: RecipeCatalogError.http(status: 500)) { try await catalog.refresh() }

        transport.route("\(base)/index.json", body: "<html>not json</html>")
        await #expect(throws: RecipeCatalogError.unreadableIndex) { try await catalog.refresh() }

        publishIndex(["kept.json"], version: 2)
        await #expect(throws: RecipeCatalogError.unreadableIndex) { try await catalog.refresh() }

        #expect(cachedNames == ["kept.json"])
    }
}
