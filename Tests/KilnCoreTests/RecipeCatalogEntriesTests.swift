import Foundation
import Testing
@testable import KilnCore

@Suite struct RecipeCatalogEntriesTests {
    let root: URL
    let store: RecipeStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-catalog-tests-\(UUID().uuidString)")
        store = RecipeStore(
            bundledDirectory: root.appendingPathComponent("bundled"),
            userDirectory: root.appendingPathComponent("user"),
            catalogDirectory: root.appendingPathComponent("catalog")
        )
        for directory in [store.bundledDirectory, store.userDirectory, store.catalogDirectory!] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func voice(_ id: String, name: String, file: String, variants: [String] = []) -> ModelRecipe {
        var recipe = ModelRecipe(
            id: id, name: name, engine: "audio.cpp",
            components: variants.isEmpty ? [.init(role: .model, repo: "o/r", file: file)] : [],
            output: .audio, defaults: nil, speech: .init(family: "f")
        )
        if !variants.isEmpty {
            recipe.variants = variants.map {
                .init(id: $0, name: $0.uppercased(), components: [.init(role: .model, repo: "o/r", file: "\(file)-\($0).gguf")])
            }
        }
        return recipe
    }

    private func writeCatalog(_ entries: [Any], as name: String = "engine.json") throws {
        let data = try JSONSerialization.data(withJSONObject: ["source": "test", "recipes": entries])
        try data.write(to: store.catalogDirectory!.appendingPathComponent(name))
    }

    private func object(_ recipe: ModelRecipe) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe))
    }

    @Test func catalogueEntriesLoadAfterCuratedAndBeforeUserRecipes() throws {
        try JSONEncoder().encode(makeRecipe(id: "zebra")).write(to: store.bundledDirectory.appendingPathComponent("zebra.json"))
        try JSONEncoder().encode(makeRecipe(id: "mine")).write(to: store.userDirectory.appendingPathComponent("mine.json"))
        try writeCatalog([try object(voice("cat-b", name: "Beta", file: "b.gguf")), try object(voice("cat-a", name: "Alpha", file: "a.gguf"))])

        let result = store.loadAll()

        #expect(result.recipes.map(\.id) == ["zebra", "cat-a", "cat-b", "mine"])
        #expect(result.catalogIDs == ["cat-a", "cat-b"])
        #expect(result.userRecipeIDs == ["mine"])
        #expect(result.failures.isEmpty)
    }

    @Test func aModelACuratedRecipeCoversIsLeftOut() throws {
        let curated = voice("curated", name: "Curated", file: "model", variants: ["q8"])
        try JSONEncoder().encode(curated).write(to: store.bundledDirectory.appendingPathComponent("curated.json"))
        try writeCatalog([
            // The same file as the curated recipe's only variant: nothing left to offer.
            try object(voice("same", name: "Same", file: "model", variants: ["q8"])),
            // One variant is covered, the other is not.
            try object(voice("partly", name: "Partly", file: "model", variants: ["q8", "bf16"])),
            try object(voice("other", name: "Other", file: "other.gguf")),
        ])

        let result = store.loadAll()

        #expect(result.recipes.map(\.id) == ["curated", "other", "partly"])
        #expect(result.recipes.first { $0.id == "partly" }?.variants?.map(\.id) == ["bf16"])
    }

    @Test func anEntryThisVersionCannotReadIsSkippedWithoutLosingTheRest() throws {
        try writeCatalog([
            ["id": "future", "name": "Future", "engine": "audio.cpp", "components": [["role": "hologram", "repo": "o/r", "file": "f"]]],
            // Decodes, but an audio model without its speech settings is not valid.
            ["id": "invalid", "name": "Invalid", "engine": "audio.cpp", "output": "audio",
             "components": [["role": "model", "repo": "o/r", "file": "f.gguf"]]],
            try object(voice("fine", name: "Fine", file: "fine.gguf")),
        ])
        try Data("not json".utf8).write(to: store.catalogDirectory!.appendingPathComponent("broken.json"))

        let result = store.loadAll()

        #expect(result.recipes.map(\.id) == ["fine"])
        #expect(result.failures.isEmpty)
    }

    @Test func aCuratedIdWinsOverACatalogueEntryWithTheSameId() throws {
        try JSONEncoder().encode(makeRecipe(id: "shared")).write(to: store.bundledDirectory.appendingPathComponent("shared.json"))
        try writeCatalog([try object(voice("shared", name: "Shared", file: "s.gguf"))])

        let result = store.loadAll()

        #expect(result.recipes.count == 1)
        #expect(result.catalogIDs.isEmpty)
    }

    @Test func theShippedCatalogueLoadsInFull() throws {
        let shipped = RecipeStore(
            bundledDirectory: curatedRecipesDirectory,
            userDirectory: root.appendingPathComponent("user"),
            catalogDirectory: curatedRecipesDirectory.deletingLastPathComponent().appendingPathComponent("catalog")
        )
        // The model files the curated recipes cover, as "repo\nfile".
        let mainRoles: Set<String> = ["model", "checkpoint", "diffusion_model"]
        func mainFiles(_ recipe: [String: Any]) -> [[String]] {
            let shared = recipe["components"] as? [[String: Any]] ?? []
            let variants = (recipe["variants"] as? [[String: Any]] ?? []).map { $0["components"] as? [[String: Any]] ?? [] }
            return (variants.isEmpty ? [shared] : variants.map { shared + $0 }).map { install in
                install.filter { mainRoles.contains($0["role"] as? String ?? "") }
                    .map { "\($0["repo"] as? String ?? "")\n\($0["file"] as? String ?? "")" }
            }
        }
        func recipes(in directory: URL, key: String?) throws -> [[String: Any]] {
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" && !["index.json", "schema.json"].contains($0.lastPathComponent) }
                .flatMap { file -> [[String: Any]] in
                    let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
                    return key.map { json[$0] as? [[String: Any]] ?? [] } ?? [json]
                }
        }
        let covered = Set(try recipes(in: curatedRecipesDirectory, key: nil).flatMap(mainFiles).joined())
        let entries = try recipes(in: shipped.catalogDirectory!, key: "recipes")
        // An entry stays in the list while at least one of its versions is not a curated recipe's file.
        let remaining = entries.filter { entry in mainFiles(entry).contains { install in !install.contains(where: covered.contains) } }

        let result = shipped.loadAll()

        // Every entry the generator wrote is readable; only those a curated recipe covers are dropped.
        #expect(!entries.isEmpty)
        #expect(result.catalogIDs.count == remaining.count)
        #expect(result.failures.isEmpty)
        for recipe in result.recipes where result.catalogIDs.contains(recipe.id) {
            let installs = recipe.hasVariants ? recipe.resolvedVariants : [recipe]
            for component in installs.flatMap(\.components) {
                #expect(component.revision != nil && component.sizeBytes != nil, "\(recipe.id): \(component.file) is not pinned")
                // Only files too small for the Hub to hash go without a checksum.
                #expect(component.sha256 != nil || component.role == .support, "\(recipe.id): \(component.file) has no sha256")
            }
        }
    }
}
