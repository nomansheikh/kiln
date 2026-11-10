import Foundation
@testable import KilnCore

/// `recipes/` at the repository root.
let curatedRecipesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
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

extension ModelRecipe {
    func with(variants: [Variant]) -> ModelRecipe {
        var copy = self
        copy.variants = variants
        return copy
    }
}
