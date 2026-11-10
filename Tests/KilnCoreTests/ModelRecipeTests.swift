import Foundation
import Testing
@testable import KilnCore

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
            .filter { $0.pathExtension == "json" && !RecipeStore.reservedFileNames.contains($0.lastPathComponent) }
        #expect(!files.isEmpty)

        // The index is what released apps fetch, so it must list exactly the recipe files.
        struct Index: Decodable { let recipes: [String] }
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: curatedRecipesDirectory.appendingPathComponent("index.json")))
        #expect(index.recipes.sorted() == files.map(\.lastPathComponent).sorted(), "run: python3 scripts/recipe.py index")

        for file in files {
            let recipe = try RecipeStore.decode(Data(contentsOf: file))
            #expect(recipe.id == file.deletingPathExtension().lastPathComponent, "file name must match the recipe id")
            #expect(recipe.engine == "sd.cpp")
            // Curated recipes must be fully pinned so downloads can be verified.
            // With variants, every variant has to be complete and pinned.
            let installs = recipe.hasVariants ? recipe.resolvedVariants : [recipe]
            for component in installs.flatMap(\.components) {
                #expect(component.revision != nil, "\(file.lastPathComponent): \(component.file) has no revision")
                #expect(component.sizeBytes != nil, "\(file.lastPathComponent): \(component.file) has no size")
                #expect(component.sha256 != nil, "\(file.lastPathComponent): \(component.file) has no sha256")
            }
        }
    }

    @Test func aVariantReplacesSharedFilesOfTheSameRoleAndKeepsTheRest() throws {
        let recipe = makeRecipe(
            components: [
                .init(role: .vae, repo: "a/b", file: "vae.safetensors", sizeBytes: 1),
                .init(role: .llm, repo: "a/b", file: "enc-default.gguf", sizeBytes: 2),
            ],
            minMemoryGB: 32
        ).with(variants: [
            .init(id: "q8", name: "Q8", components: [
                .init(role: .diffusionModel, repo: "a/b", file: "dn-q8.gguf", sizeBytes: 80),
            ]),
            .init(id: "q4", name: "Q4", components: [
                .init(role: .diffusionModel, repo: "a/b", file: "dn-q4.gguf", sizeBytes: 40),
                .init(role: .llm, repo: "a/b", file: "enc-q4.gguf", sizeBytes: 1),
            ], minMemoryGB: 16),
        ])
        try recipe.validate()

        let q8 = recipe.resolved("q8")
        #expect(q8.components.map(\.file).sorted() == ["dn-q8.gguf", "enc-default.gguf", "vae.safetensors"])
        #expect(q8.totalSizeBytes == 83)
        #expect(q8.minMemoryGB == 32)
        #expect(q8.selectedVariantID == "q8")

        let q4 = recipe.resolved("q4")
        #expect(q4.components.map(\.file).sorted() == ["dn-q4.gguf", "enc-q4.gguf", "vae.safetensors"])
        #expect(q4.minMemoryGB == 16)
        #expect(recipe.resolved("nope") == recipe)
        #expect(recipe.resolvedVariants.map(\.selectedVariantID) == ["q8", "q4"])
    }

    @Test func variantsRoundTripThroughJSONWithoutTheSelection() throws {
        let recipe = makeRecipe().with(variants: [
            .init(id: "q8", name: "Q8", components: [.init(role: .vae, repo: "a/b", file: "v.safetensors")], minMemoryGB: 24),
        ])

        let decoded = try RecipeStore.decode(JSONEncoder().encode(recipe.resolved("q8")))

        // Which variant is selected is the app's choice, not part of the file.
        #expect(decoded.selectedVariantID == nil)
        #expect(decoded.variants == recipe.variants)
    }

    @Test func rejectsBrokenVariants() {
        let part = ModelRecipe.Component(role: .vae, repo: "a/b", file: "v.safetensors")
        let duplicateID = makeRecipe().with(variants: [
            .init(id: "q8", name: "A", components: [part]), .init(id: "q8", name: "B", components: [part]),
        ])
        let badID = makeRecipe().with(variants: [.init(id: "Q 8", name: "A", components: [part])])
        let unnamed = makeRecipe().with(variants: [.init(id: "q8", name: " ", components: [part])])
        let empty = makeRecipe().with(variants: [.init(id: "q8", name: "A", components: [])])
        let clashing = makeRecipe().with(variants: [.init(id: "q8", name: "A", components: [part, part])])

        #expect(throws: RecipeValidationError.invalidVariant("q8")) { try duplicateID.validate() }
        #expect(throws: RecipeValidationError.invalidVariant("Q 8")) { try badID.validate() }
        #expect(throws: RecipeValidationError.invalidVariant("q8")) { try unnamed.validate() }
        #expect(throws: RecipeValidationError.noComponents) { try empty.validate() }
        #expect(throws: RecipeValidationError.duplicateRole(.vae)) { try clashing.validate() }
    }

    @Test func aRecipeMayKeepAllItsFilesInVariants() throws {
        let recipe = makeRecipe(components: []).with(variants: [
            .init(id: "only", name: "Only", components: [.init(role: .checkpoint, repo: "a/b", file: "m.safetensors")]),
        ])
        try recipe.validate()
        #expect(recipe.resolved("only").components.count == 1)
    }

    @Test func decodesEncoderRolesAndModelSettings() throws {
        let json = """
        {"id": "flux-like", "name": "Flux-like", "engine": "sd.cpp",
         "components": [
           {"role": "diffusion_model", "repo": "a/b", "file": "dn.gguf"},
           {"role": "clip_l", "repo": "a/b", "file": "clip_l.safetensors"},
           {"role": "clip_g", "repo": "a/b", "file": "clip_g.safetensors"},
           {"role": "t5xxl", "repo": "a/b", "file": "t5xxl.safetensors"},
           {"role": "vae", "repo": "a/b", "file": "ae.safetensors"}
         ],
         "defaults": {"steps": 4, "cfg": 1, "sampler": "euler", "width": 1024, "height": 1024,
                      "scheduler": "simple", "guidance": 3.5, "flow_shift": 3.0}}
        """
        let recipe = try RecipeStore.decode(Data(json.utf8))

        #expect(recipe.components.map(\.role) == [.diffusionModel, .clipL, .clipG, .t5xxl, .vae])
        #expect(recipe.defaults.scheduler == "simple")
        #expect(recipe.defaults.guidance == 3.5)
        #expect(recipe.defaults.flowShift == 3.0)
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
