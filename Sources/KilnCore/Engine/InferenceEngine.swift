import Foundation

public struct GenerationRequest: Codable, Sendable, Equatable {
    public var prompt: String
    public var negativePrompt: String
    public var width: Int
    public var height: Int
    public var steps: Int
    public var cfg: Double
    public var sampler: String
    public var sigmas: [Double]?
    public var seed: Int64

    public init(
        prompt: String,
        negativePrompt: String = "",
        width: Int,
        height: Int,
        steps: Int,
        cfg: Double,
        sampler: String,
        sigmas: [Double]? = nil,
        seed: Int64
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.width = width
        self.height = height
        self.steps = steps
        self.cfg = cfg
        self.sampler = sampler
        self.sigmas = sigmas
        self.seed = seed
    }

    /// A request using the recipe's recommended settings.
    public init(prompt: String, negativePrompt: String = "", defaults: ModelRecipe.GenerationDefaults, seed: Int64) {
        self.init(
            prompt: prompt,
            negativePrompt: negativePrompt,
            width: defaults.width,
            height: defaults.height,
            steps: defaults.steps,
            cfg: defaults.cfg,
            sampler: defaults.sampler,
            sigmas: defaults.sigmas,
            seed: seed
        )
    }

    public static func randomSeed() -> Int64 {
        Int64.random(in: 0...Int64(UInt32.max))
    }
}

public struct GenerationProgress: Sendable, Equatable {
    public enum Stage: Sendable, Equatable {
        case preparing
        case encodingPrompt
        case sampling
        case decoding
        case other(String)
    }

    public var stage: Stage
    public var completed: Int
    /// Zero when the engine does not know the total.
    public var total: Int

    public init(stage: Stage, completed: Int, total: Int) {
        self.stage = stage
        self.completed = completed
        self.total = total
    }

    public var fraction: Double? {
        total > 0 ? min(1, Double(completed) / Double(total)) : nil
    }
}

/// Raw 8-bit pixels, row by row, `channels` bytes per pixel.
public struct GeneratedImage: Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var channels: Int
    public var pixels: Data

    public init(width: Int, height: Int, channels: Int, pixels: Data) {
        self.width = width
        self.height = height
        self.channels = channels
        self.pixels = pixels
    }
}

public enum GenerationEvent: Sendable, Equatable {
    case loadingModel
    case progress(GenerationProgress)
    /// A rough, low-resolution look at the image so far.
    case preview(GeneratedImage)
    case finished(GeneratedImage)
}

public enum EngineError: Error, Equatable, LocalizedError {
    case busy
    case unsupportedEngine(String)
    case missingComponents([String])
    case helperUnavailable(String)
    case modelLoadFailed(detail: String)
    case outOfMemory
    case crashed(detail: String)
    case generationFailed(detail: String)
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .busy:
            "Another image is still being generated."
        case .unsupportedEngine(let engine):
            "This model needs the \"\(engine)\" engine, which this version of Kiln does not include."
        case .missingComponents(let files):
            "This model is missing files: \(files.joined(separator: ", ")). Download it again from Models."
        case .helperUnavailable(let reason):
            "The image engine could not be started: \(reason)"
        case .modelLoadFailed(let detail):
            Self.join("The model could not be loaded. Its files may be damaged or unsupported.", detail)
        case .outOfMemory:
            "This Mac ran out of memory. Try a smaller image size, a smaller quantization, or close other apps."
        case .crashed(let detail):
            Self.join("The image engine stopped unexpectedly.", detail)
        case .generationFailed(let detail):
            Self.join("The image could not be generated.", detail)
        case .invalidOutput:
            "The image engine returned data Kiln could not read."
        }
    }

    private static func join(_ message: String, _ detail: String) -> String {
        detail.isEmpty ? message : "\(message)\n\(detail)"
    }
}

public protocol InferenceEngine: Sendable {
    /// Runs one generation off the main thread. The stream ends after `.finished`.
    /// Cancelling the consuming task cancels the generation.
    func generate(recipe: ModelRecipe, request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error>

    /// Releases the loaded model and its memory.
    func shutdown() async
}
