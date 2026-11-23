import Foundation

/// Wire format shared with the `kiln-engine` helper: one JSON object per line.
enum EngineMessage {
    enum Event: Equatable {
        case ready(version: String, commit: String)
        case loading
        case progress(stage: String, completed: Int, total: Int)
        case image(path: String, width: Int, height: Int, channels: Int)
        case preview(path: String, width: Int, height: Int, channels: Int)
        /// A finished transcript, in a UTF-8 file.
        case text(path: String)
        /// Finished sound, in a file of raw interleaved 32-bit floats.
        case audio(path: String, sampleRate: Int, channels: Int, frames: Int)
        /// A finished 3D object, in a GLB file.
        case object(path: String)
        case cancelled
        case error(code: String, message: String)
        case idle

        /// The file the helper says it wrote, for the events that name one.
        var path: String? {
            switch self {
            case .image(let path, _, _, _), .preview(let path, _, _, _), .audio(let path, _, _, _), .text(let path),
                 .object(let path): path
            default: nil
            }
        }
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
        var sampleRate: Int?
        var frames: Int?
        var code: String?

        enum CodingKeys: String, CodingKey {
            case type, version, commit, stage, completed, total, path, width, height, channels, frames, code, message
            case sampleRate = "sample_rate"
        }
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
        case "image", "preview":
            guard let path = raw.path, let width = raw.width, let height = raw.height, let channels = raw.channels else {
                return nil
            }
            return raw.type == "image"
                ? .image(path: path, width: width, height: height, channels: channels)
                : .preview(path: path, width: width, height: height, channels: channels)
        case "text":
            return raw.path.map { .text(path: $0) }
        case "audio":
            guard let path = raw.path, let sampleRate = raw.sampleRate, let channels = raw.channels, let frames = raw.frames else {
                return nil
            }
            return .audio(path: path, sampleRate: sampleRate, channels: channels, frames: frames)
        case "object":
            return raw.path.map { .object(path: $0) }
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
            var clipL: String?
            var clipG: String?
            var t5xxl: String?
            var flashAttention: Bool

            enum CodingKeys: String, CodingKey {
                case checkpoint, llm, vae, t5xxl
                case diffusionModel = "diffusion_model"
                case clipL = "clip_l"
                case clipG = "clip_g"
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
            /// File holding the source image as raw RGB at exactly `width` by `height`.
            var initImage: String?
            var strength: Double?
            var scheduler: String?
            var guidance: Double?
            var flowShift: Double?

            enum CodingKeys: String, CodingKey {
                case prompt, width, height, steps, cfg, sampler, sigmas, seed, strength, scheduler, guidance
                case flowShift = "flow_shift"
                case negativePrompt = "negative_prompt"
                case initImage = "init_image"
            }
        }

        let type = "generate"
        var model: Model
        var params: Params
        var output: String
        /// File the helper overwrites with a rough picture after each step.
        var preview: String
    }

    static func generateCommand(
        recipe: ModelRecipe,
        storage: ModelStorage,
        request: GenerationRequest,
        output: URL,
        preview: URL,
        initImage: URL? = nil
    ) throws -> Data {
        guard let settings = request.image else {
            throw EngineError.generationFailed(detail: "The request has no image settings.")
        }
        func path(_ role: ModelRecipe.ComponentRole) -> String? {
            recipe.components.first { $0.role == role }.map { storage.url(for: $0).path }
        }
        let command = GenerateCommand(
            model: .init(
                checkpoint: path(.checkpoint),
                diffusionModel: path(.diffusionModel),
                llm: path(.llm),
                vae: path(.vae),
                clipL: path(.clipL),
                clipG: path(.clipG),
                t5xxl: path(.t5xxl),
                flashAttention: recipe.defaults?.flashAttention ?? false
            ),
            params: .init(
                prompt: request.prompt,
                negativePrompt: settings.negativePrompt,
                width: settings.width,
                height: settings.height,
                steps: settings.steps,
                cfg: settings.cfg,
                sampler: settings.sampler,
                sigmas: settings.sigmas,
                seed: settings.seed,
                initImage: initImage?.path,
                strength: initImage == nil ? nil : settings.strength,
                // These belong to the model, not to one prompt, so they come from the recipe.
                scheduler: recipe.defaults?.scheduler,
                guidance: recipe.defaults?.guidance,
                flowShift: recipe.defaults?.flowShift
            ),
            output: output.path,
            preview: preview.path
        )
        return try line(command)
    }

    static let cancelCommand = Data(#"{"type":"cancel"}"#.utf8) + Data([0x0A])

    static func line(_ value: some Encodable) throws -> Data {
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
        case "transcribing": .transcribing
        case "speaking": .speaking
        case "step": .building
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
