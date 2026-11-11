import Foundation

extension ModelRecipe {
    /// A recipe for one all-in-one checkpoint file picked from a Hugging Face repo.
    ///
    /// Settings are stable-diffusion.cpp's own defaults, since nothing better is
    /// known about an arbitrary file. Models split into several parts need a
    /// hand-written recipe instead.
    public static func singleFile(_ file: HFFile, in info: HFModelInfo) -> ModelRecipe {
        let side = file.name.lowercased().contains("xl") ? 1024 : 512
        return ModelRecipe(
            id: generatedID(for: file, in: info),
            name: file.name,
            engine: StableDiffusionCppEngine.engineID,
            components: [
                Component(
                    role: .checkpoint,
                    repo: info.id,
                    file: file.path,
                    revision: info.revision,
                    sizeBytes: file.sizeBytes,
                    sha256: file.sha256
                ),
            ],
            defaults: GenerationDefaults(steps: 20, cfg: 7.0, sampler: "euler", width: side, height: side),
            licenseNote: info.license.map { "License: \($0). See the model page on Hugging Face." }
        )
    }
}

extension ModelRecipe {
    /// The id of a recipe Kiln writes for a file picked from a Hugging Face repo.
    static func generatedID(for file: HFFile, in info: HFModelInfo) -> String {
        let slug = "\(info.id)-\(file.name)".lowercased().map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-")
                ? character : "-"
        }
        return String(slug).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }

    /// True for a one-file recipe whose file does not look like a whole model, for
    /// example a text encoder downloaded by itself. Such a recipe cannot generate images.
    public var isIncompleteSingleFile: Bool {
        guard components.count == 1, let component = components.first, component.role == .checkpoint else { return false }
        return !HFFile(path: component.file, sizeBytes: component.sizeBytes, sha256: nil).looksLikeStandaloneCheckpoint
    }
}

extension RecipeStore {
    /// Writes a recipe into the user directory, replacing one with the same id.
    public func save(_ recipe: ModelRecipe) throws {
        try recipe.validate()
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(recipe).write(to: userDirectory.appendingPathComponent("\(recipe.id).json"), options: .atomic)
    }

    /// Deletes a recipe the user added. Bundled recipes cannot be removed.
    public func removeUserRecipe(id: String) throws {
        let file = userDirectory.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}
