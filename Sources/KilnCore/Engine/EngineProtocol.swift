import Foundation

/// Wire format shared with the `kiln-engine` helper: one JSON object per line.
enum EngineMessage {
    enum Event: Equatable {
        case ready(version: String, commit: String)
        case loading
        case progress(stage: String, completed: Int, total: Int)
        case image(path: String, width: Int, height: Int, channels: Int)
        case cancelled
        case error(code: String, message: String)
        case idle
    }

    private struct RawEvent: Decodable {
        let type: String
        var version: String?
        var commit: String?
        var stage: String?
        var completed: Int?
        var total: Int?
        var path: String?
        var width: Int?
        var height: Int?
        var channels: Int?
        var code: String?
        var message: String?
    }

    /// Nil for lines that are not a known event, so newer helpers stay compatible.
    static func decodeEvent(_ line: String) -> Event? {
        guard let raw = try? JSONDecoder().decode(RawEvent.self, from: Data(line.utf8)) else { return nil }
        switch raw.type {
        case "ready":
            return .ready(version: raw.version ?? "", commit: raw.commit ?? "")
        case "loading":
            return .loading
        case "progress":
            return .progress(stage: raw.stage ?? "", completed: raw.completed ?? 0, total: raw.total ?? 0)
        case "image":
            guard let path = raw.path, let width = raw.width, let height = raw.height, let channels = raw.channels else {
                return nil
            }
            return .image(path: path, width: width, height: height, channels: channels)
        case "cancelled":
            return .cancelled
        case "error":
            return .error(code: raw.code ?? "", message: raw.message ?? "")
        case "idle":
            return .idle
        default:
            return nil
        }
    }

    private struct GenerateCommand: Encodable {
        struct Model: Encodable {
            var checkpoint: String?
            var diffusionModel: String?
            var llm: String?
            var vae: String?
            var flashAttention: Bool

            enum CodingKeys: String, CodingKey {
                case checkpoint, llm, vae
                case diffusionModel = "diffusion_model"
                case flashAttention = "flash_attention"
            }
        }

        struct Params: Encodable {
            var prompt: String
            var negativePrompt: String
            var width: Int
            var height: Int
            var steps: Int
            var cfg: Double
            var sampler: String
            var sigmas: [Double]?
            var seed: Int64

            enum CodingKeys: String, CodingKey {
                case prompt, width, height, steps, cfg, sampler, sigmas, seed
                case negativePrompt = "negative_prompt"
            }
        }

        let type = "generate"
        var model: Model
        var params: Params
        var output: String
    }

    static func generateCommand(
        recipe: ModelRecipe,
        storage: ModelStorage,
        request: GenerationRequest,
        output: URL
    ) throws -> Data {
        func path(_ role: ModelRecipe.ComponentRole) -> String? {
            recipe.components.first { $0.role == role }.map { storage.url(for: $0).path }
        }
        let command = GenerateCommand(
            model: .init(
                checkpoint: path(.checkpoint),
                diffusionModel: path(.diffusionModel),
                llm: path(.llm),
                vae: path(.vae),
                flashAttention: recipe.defaults.flashAttention ?? false
            ),
            params: .init(
                prompt: request.prompt,
                negativePrompt: request.negativePrompt,
                width: request.width,
                height: request.height,
                steps: request.steps,
                cfg: request.cfg,
                sampler: request.sampler,
                sigmas: request.sigmas,
                seed: request.seed
            ),
            output: output.path
        )
        return try line(command)
    }

    static let cancelCommand = Data(#"{"type":"cancel"}"#.utf8) + Data([0x0A])

    private static func line(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        // Model keys must be stable: the helper reloads the model when they change.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value) + Data([0x0A])
    }

    static func stage(_ name: String) -> GenerationProgress.Stage {
        switch name {
        case "preparing": .preparing
        case "conditioning": .encodingPrompt
        case "sampling": .sampling
        case "vae_decode": .decoding
        default: .other(name)
        }
    }

    /// Whether the helper's last log lines point at memory exhaustion.
    static func indicatesOutOfMemory(_ lines: [String]) -> Bool {
        let markers = [
            "out of memory",
            "outofmemory",
            "insufficient memory",
            "failed to allocate",
        ]
        return lines.contains { line in
            let lowered = line.lowercased()
            return markers.contains { lowered.contains($0) }
        }
    }
}
