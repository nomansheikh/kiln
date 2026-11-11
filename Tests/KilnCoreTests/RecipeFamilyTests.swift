import Foundation
import Testing
@testable import KilnCore

@Suite struct RecipeFamilyTests {
    static let gib: Int64 = 1_073_741_824

    /// A recipe split into parts, as the library hands it over: variant already merged.
    static func baseRecipe(baseModel: String? = "Tongyi-MAI/Z-Image-Turbo") -> ModelRecipe {
        var recipe = makeRecipe(
            id: "z-image-turbo",
            components: [
                .init(role: .vae, repo: "Comfy-Org/z_image_turbo", file: "split_files/vae/ae.safetensors", sizeBytes: 300),
                .init(role: .llm, repo: "unsloth/Qwen3-4B-GGUF", file: "Qwen3-4B-Q8_0.gguf", sizeBytes: 4_000),
                .init(role: .diffusionModel, repo: "leejet/Z-Image-Turbo-GGUF", file: "z_image_turbo-Q8_0.gguf", sizeBytes: 6_000),
            ]
        )
        recipe.baseModel = baseModel
        recipe.licenseNote = "Apache-2.0."
        recipe.minMemoryGB = 24
        recipe.tested = true
        return recipe
    }

    static func info(
        tags: [String] = ["gguf", "license:apache-2.0", "base_model:Tongyi-MAI/Z-Image-Turbo", "base_model:quantized:Tongyi-MAI/Z-Image-Turbo"],
        files: [(String, Int64)] = [("z-image-turbo-Q4_K_M.gguf", 4 * gib), ("z-image-turbo-Q8_0.gguf", 7 * gib)]
    ) throws -> HFModelInfo {
        let siblings = files.map { #"{"rfilename": "\#($0.0)", "size": \#($0.1), "lfs": {"sha256": "\#(String(repeating: "a", count: 64))"}}"# }
        let tagList = tags.map { "\"\($0)\"" }.joined(separator: ", ")
        let body = #"{"id": "unsloth/Z-Image-Turbo-GGUF", "sha": "abc123", "tags": [\#(tagList)], "siblings": [\#(siblings.joined(separator: ", "))]}"#
        return try JSONDecoder().decode(HFModelInfo.self, from: Data(body.utf8))
    }

    @Test func readsBaseModelsFromTagsAndIgnoresAdapters() throws {
        let tags = ["base_model:a/b", "base_model:quantized:a/b", "base_model:finetune:c/d", "base_model:merge:e/f", "base_model:adapter:g/h"]
        #expect(try Self.info(tags: tags).baseModels == ["a/b", "c/d", "e/f"])
        #expect(try Self.info(tags: ["gguf"]).baseModels.isEmpty)
    }

    @Test func matchesARepoOfTheSameBaseModel() throws {
        #expect(Self.baseRecipe().isSameFamily(as: try Self.info()))
        #expect(!Self.baseRecipe().isSameFamily(as: try Self.info(tags: ["base_model:quantized:Qwen/Qwen-Image-2.1"])))
        #expect(!Self.baseRecipe(baseModel: nil).isSameFamily(as: try Self.info()))
        // A LoRA for the model is not the model.
        #expect(!Self.baseRecipe().isSameFamily(as: try Self.info(tags: ["base_model:adapter:Tongyi-MAI/Z-Image-Turbo"])))
    }

    @Test func recipeWithoutASeparateDenoiserHasNoFamily() throws {
        var checkpoint = makeRecipe()
        checkpoint.baseModel = "Tongyi-MAI/Z-Image-Turbo"
        #expect(!checkpoint.isSameFamily(as: try Self.info()))
    }

    @Test func adaptedRecipeSwapsOnlyTheDenoiser() throws {
        let base = Self.baseRecipe()
        let info = try Self.info()
        let file = try #require(info.files.first)

        let recipe = try #require(base.adapted(to: file, in: info))

        #expect(recipe.id == "unsloth-z-image-turbo-gguf-z-image-turbo-q4-k-m.gguf")
        #expect(recipe.name == "z-image-turbo-Q4_K_M.gguf")
        #expect(recipe.components.filter { $0.role != .diffusionModel } == base.components.filter { $0.role != .diffusionModel })
        let denoiser = try #require(recipe.components.first { $0.role == .diffusionModel })
        #expect(denoiser == .init(
            role: .diffusionModel, repo: "unsloth/Z-Image-Turbo-GGUF", file: "z-image-turbo-Q4_K_M.gguf",
            revision: "abc123", sizeBytes: 4 * Self.gib, sha256: String(repeating: "a", count: 64)
        ))
        #expect(recipe.defaults == base.defaults)
        // Nothing is known about how the new pairing behaves.
        #expect(recipe.tested == nil)
        #expect(recipe.minMemoryGB == nil)
        #expect(recipe.baseModel == nil)
        #expect(recipe.licenseNote == "z-image-turbo-Q4_K_M.gguf: apache-2.0 license. See the model page on Hugging Face. "
            + "Other files and settings are from Kiln's Test recipe, whose note reads: Apache-2.0.")
        try recipe.validate()
    }

    @Test func refusesAFileThatIsNotADenoiserOrARepoOfAnotherModel() throws {
        let info = try Self.info(files: [("vae/ae.safetensors", 300)])
        #expect(Self.baseRecipe().adapted(to: try #require(info.files.first), in: info) == nil)
        let other = try Self.info(tags: ["base_model:quantized:Qwen/Qwen-Image-2.1"])
        #expect(Self.baseRecipe().adapted(to: try #require(other.files.first), in: other) == nil)
    }

    @Test(arguments: [
        ("z-image-turbo-Q4_K_M.gguf", true),
        ("z_image_turbo_bf16.safetensors", true),
        ("split_files/diffusion_models/z_image_turbo_bf16.safetensors", true),
        ("transformer/diffusion_pytorch_model-00001-of-00003.safetensors", false),
        ("split_files/text_encoders/qwen_3_4b.safetensors", false),
        ("vae/diffusion_pytorch_model.safetensors", false),
        ("ae.safetensors", false),
        ("mmproj-model-F16.gguf", false),
        ("style-lora.safetensors", false),
        ("README.md", false),
    ])
    func guessesWhichFilesAreDenoisers(path: String, expected: Bool) {
        #expect(HFFile(path: path, sizeBytes: nil, sha256: nil).looksLikeDenoiser == expected)
    }

    @Test func bestDenoiserCountsTheFilesThatLoadBesideIt() throws {
        let info = try Self.info()
        let usable = Double(16 * Self.gib)
        #expect(info.bestDenoiser(usableBytes: usable, companionBytes: 4 * Self.gib)?.name == "z-image-turbo-Q8_0.gguf")
        #expect(info.bestDenoiser(usableBytes: usable, companionBytes: 8 * Self.gib)?.name == "z-image-turbo-Q4_K_M.gguf")
        // Nothing fits: the smallest is still offered.
        #expect(info.bestDenoiser(usableBytes: 0, companionBytes: 0)?.name == "z-image-turbo-Q4_K_M.gguf")
        #expect(try Self.info(files: [("vae/ae.safetensors", 300)]).bestDenoiser(usableBytes: usable, companionBytes: 0) == nil)
    }

    @Test func baseModelIsDecodedAndValidated() throws {
        let json = #"{"id": "m", "name": "M", "engine": "sd.cpp", "base_model": "owner/name", "components": [{"role": "checkpoint", "repo": "a/b", "file": "m.safetensors"}], "defaults": {"steps": 1, "cfg": 1, "sampler": "euler", "width": 64, "height": 64}}"#
        var recipe = try JSONDecoder().decode(ModelRecipe.self, from: Data(json.utf8))
        #expect(recipe.baseModel == "owner/name")
        try recipe.validate()
        recipe.baseModel = "not a repo"
        #expect(throws: RecipeValidationError.invalidRepo("not a repo")) { try recipe.validate() }
    }
}
