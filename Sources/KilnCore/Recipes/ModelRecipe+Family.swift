import Foundation

extension HFModelInfo {
    /// Repos this one was made from by quantizing, fine-tuning or merging, as its
    /// `base_model` tags state. Adapters (LoRAs) are left out: they are not a model.
    public var baseModels: [String] {
        var result: [String] = []
        for relation in ["quantized", "finetune", "merge"] {
            let prefix = "base_model:\(relation):"
            for tag in tags where tag.hasPrefix(prefix) {
                let repo = String(tag.dropFirst(prefix.count))
                if !result.contains(repo) { result.append(repo) }
            }
        }
        return result
    }

    /// Files that could stand in for a recipe's denoiser, largest first.
    public var denoiserFiles: [HFFile] {
        weightFiles.filter(\.looksLikeDenoiser)
    }

    /// The denoiser to offer as this repo's one-click download. `companionBytes` is
    /// the size of the files that load beside it. Same preference as
    /// `bestStandaloneCheckpoint`: the largest that fits comfortably, else the smallest.
    public func bestDenoiser(usableBytes: Double, companionBytes: Int64) -> HFFile? {
        let candidates = denoiserFiles
        let comfortable = candidates.filter {
            Double(($0.sizeBytes ?? 0) + companionBytes) <= usableBytes * MemoryFitEstimator.comfortableShare
        }
        return comfortable.max { ($0.sizeBytes ?? 0) < ($1.sizeBytes ?? 0) }
            ?? candidates.min { ($0.sizeBytes ?? .max) < ($1.sizeBytes ?? .max) }
    }
}

extension HFFile {
    /// Whether the file is plausibly a denoiser in one file. This is a guess from the
    /// path: weights that are not split into shards and whose path does not mark them
    /// as another part (a VAE, text encoder, LoRA and so on).
    public var looksLikeDenoiser: Bool {
        let lowered = path.lowercased()
        guard isWeights, !isVisionProjector, lowered.firstMatch(of: /-\d+-of-\d+\./) == nil else { return false }
        if name.lowercased() == "ae.safetensors" { return false }
        let otherParts = ["vae", "clip", "t5", "encoder", "lora", "mmproj", "controlnet", "adapter"]
        return !otherParts.contains { lowered.contains($0) }
    }
}

extension ModelRecipe {
    /// Whether the repo holds the same model as this recipe's denoiser, so that one
    /// of its files can run with this recipe's other files and settings.
    public func isSameFamily(as info: HFModelInfo) -> Bool {
        guard let baseModel, components.contains(where: { $0.role == .diffusionModel }) else { return false }
        return info.baseModels.contains(baseModel)
    }

    /// This recipe with its denoiser replaced by a file from another repo of the
    /// same model. The text encoder, VAE and settings are kept. Call it on a recipe
    /// with its variant already merged in.
    ///
    /// The pairing is inferred from the repo's `base_model` tag, not tested: a
    /// fine-tune that needs other settings will load but may give poor images.
    public func adapted(to file: HFFile, in info: HFModelInfo) -> ModelRecipe? {
        guard isSameFamily(as: info), file.looksLikeDenoiser else { return nil }
        let denoiser = Component(
            role: .diffusionModel,
            repo: info.id,
            file: file.path,
            revision: info.revision,
            sizeBytes: file.sizeBytes,
            sha256: file.sha256
        )
        let notes = [
            info.license.map { "\(file.name): \($0) license. See the model page on Hugging Face." },
            licenseNote.map { "Other files and settings are from Kiln's \(name) recipe, whose note reads: \($0)" },
        ]
        return ModelRecipe(
            id: Self.generatedID(for: file, in: info),
            name: file.name,
            engine: engine,
            components: components.filter { $0.role != .diffusionModel } + [denoiser],
            defaults: defaults,
            licenseNote: notes.compactMap { $0 }.joined(separator: " ")
        )
    }
}
