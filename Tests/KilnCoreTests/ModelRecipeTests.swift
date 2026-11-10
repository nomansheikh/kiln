import Foundation
import Testing
@testable import KilnCore

/// `recipes/` at the repository root.
let curatedRecipesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("recipes")

func makeRecipe(
    id: String = "test-model",
    components: [ModelRecipe.Component] = [
        .init(role: .checkpoint, repo: "owner/name", file: "model.safetensors", sizeBytes: 1_000),
    ],
    defaults: ModelRecipe.GenerationDefaults = .init(steps: 8, cfg: 1, sampler: "euler", width: 1024, height: 1024),
    minMemoryGB: Double? = nil
) -> ModelRecipe {
    ModelRecipe(id: id, name: "Test", engine: "sd.cpp", components: components, defaults: defaults, minMemoryGB: minMemoryGB)
}

@Suite struct ModelRecipeTests {
    @Test func decodesTheSpecExample() throws {
        let json = """
        {
          "id": "qwen-image-2.1-turbo",
          "name": "Qwen-Image 2.1 Turbo",
          "engine": "sd.cpp",
          "components": [
            {"role": "llm", "repo": "AtomicChat/a", "file": "enc-Q8_0.gguf"},
            {"role": "diffusion_model", "repo": "AtomicChat/b", "file": "dn.gguf"},
            {"role": "vae", "repo": "Comfy-Org/c", "file": "vae/v.safetensors"}
          ],
          "defaults": {"steps": 8, "cfg": 1.0, "sampler": "euler", "width": 1024, "height": 1024},
          "license_note": "note",
          "min_memory_gb": 16
        }
        """
        let recipe = try RecipeStore.decode(Data(json.utf8))

        #expect(recipe.id == "qwen-image-2.1-turbo")
        #expect(recipe.components.map(\.role) == [.llm, .diffusionModel, .vae])
        #expect(recipe.defaults.steps == 8)
        #expect(recipe.licenseNote == "note")
        #expect(recipe.minMemoryGB == 16)
        #expect(recipe.totalSizeBytes == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let recipe = makeRecipe(
            defaults: .init(steps: 2, cfg: 1, sampler: "euler", width: 512, height: 512, sigmas: [1, 0.5, 0], flashAttention: true),
            minMemoryGB: 8
        )
        let decoded = try RecipeStore.decode(JSONEncoder().encode(recipe))
        #expect(decoded == recipe)
    }

    @Test func everyCuratedRecipeIsValid() throws {
        let files = try FileManager.default.contentsOfDirectory(at: curatedRecipesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(!files.isEmpty)

        for file in files {
            let recipe = try RecipeStore.decode(Data(contentsOf: file))
            #expect(recipe.id == file.deletingPathExtension().lastPathComponent, "file name must match the recipe id")
            #expect(recipe.engine == "sd.cpp")
            // Curated recipes must be fully pinned so downloads can be verified.
            for component in recipe.components {
                #expect(component.revision != nil, "\(file.lastPathComponent): \(component.file) has no revision")
                #expect(component.sizeBytes != nil, "\(file.lastPathComponent): \(component.file) has no size")
                #expect(component.sha256 != nil, "\(file.lastPathComponent): \(component.file) has no sha256")
            }
        }
    }

    @Test func sumsComponentSizes() {
        let recipe = makeRecipe(components: [
            .init(role: .llm, repo: "a/b", file: "one.gguf", sizeBytes: 10),
            .init(role: .vae, repo: "a/b", file: "two.gguf", sizeBytes: 5),
        ])
        #expect(recipe.totalSizeBytes == 15)
    }

    @Test func rejectsUnknownRole() {
        let json = """
        {"id": "x", "name": "X", "engine": "sd.cpp",
         "components": [{"role": "upscaler", "repo": "a/b", "file": "f.gguf"}],
         "defaults": {"steps": 1, "cfg": 1, "sampler": "euler", "width": 64, "height": 64}}
        """
        #expect(throws: DecodingError.self) { try RecipeStore.decode(Data(json.utf8)) }
    }

    @Test(arguments: ["", "Has Spaces", "UPPER", "../escape", ".hidden"])
    func rejectsBadID(id: String) {
        #expect(throws: RecipeValidationError.invalidID(id)) { try makeRecipe(id: id).validate() }
    }

    @Test(arguments: ["../outside.gguf", "/etc/passwd", "a//b.gguf", "a/./b.gguf", "a\\b.gguf", ""])
    func rejectsUnsafeFilePath(file: String) {
        let recipe = makeRecipe(components: [.init(role: .checkpoint, repo: "a/b", file: file)])
        #expect(throws: RecipeValidationError.unsafeFilePath(file)) { try recipe.validate() }
    }

    @Test(arguments: ["noslash", "a/b/c", "/b", "a/", "../b"])
    func rejectsBadRepo(repo: String) {
        let recipe = makeRecipe(components: [.init(role: .checkpoint, repo: repo, file: "f.gguf")])
        #expect(throws: RecipeValidationError.invalidRepo(repo)) { try recipe.validate() }
    }

    @Test func rejectsDuplicateRoles() {
        let recipe = makeRecipe(components: [
            .init(role: .vae, repo: "a/b", file: "one.safetensors"),
            .init(role: .vae, repo: "a/b", file: "two.safetensors"),
        ])
        #expect(throws: RecipeValidationError.duplicateRole(.vae)) { try recipe.validate() }
    }

    @Test func rejectsEmptyComponents() {
        #expect(throws: RecipeValidationError.noComponents) { try makeRecipe(components: []).validate() }
    }

    @Test func rejectsMalformedChecksumAndSize() {
        let badHash = makeRecipe(components: [.init(role: .checkpoint, repo: "a/b", file: "f.gguf", sha256: "abc123")])
        #expect(throws: RecipeValidationError.invalidSHA256(file: "f.gguf")) { try badHash.validate() }

        let badSize = makeRecipe(components: [.init(role: .checkpoint, repo: "a/b", file: "f.gguf", sizeBytes: 0)])
        #expect(throws: RecipeValidationError.invalidSize(file: "f.gguf")) { try badSize.validate() }
    }

    @Test func rejectsSigmaCountThatDoesNotMatchSteps() {
        let recipe = makeRecipe(defaults: .init(steps: 8, cfg: 1, sampler: "euler", width: 64, height: 64, sigmas: [1, 0]))
        #expect(throws: RecipeValidationError.self) { try recipe.validate() }
    }
}
