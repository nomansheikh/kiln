import Foundation

public struct GenerationProgress: Sendable, Equatable {
    public enum Stage: Sendable, Equatable {
        case preparing
        case encodingPrompt
        case sampling
        case decoding
        case transcribing
        case speaking
        /// One step of several in making a 3D object.
        case building
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

/// What a finished generation produced.
public enum GenerationOutput: Sendable, Hashable {
    case image(GeneratedImage)
    case text(String)
    case audio(GeneratedAudio)
    case mesh(GeneratedMesh)
}

public enum GenerationEvent: Sendable, Equatable {
    case loadingModel
    case progress(GenerationProgress)
    /// A rough, low-resolution look at the image so far.
    case preview(GeneratedImage)
    case finished(GenerationOutput)
}

public enum EngineError: Error, Equatable, LocalizedError {
    case busy
    case unsupportedEngine(String)
    case missingComponents([String])
    case unreadableSourceImage
    case missingSourceImage
    case missingAudio
    case missingText
    case missingInstruction
    case missingReference
    case missingReferenceText
    case unreadableReference
    case tooManySpeakers(Int)
    case missingSpeakerVoice(String)
    case scriptStopped(finished: Int, total: Int, detail: String)
    case unknownVoice(String)
    case unreadableAudio
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
        case .unreadableSourceImage:
            "The attached image could not be read. Try a PNG or JPEG file."
        case .missingSourceImage:
            "This model makes a 3D object from a picture. Attach an image first."
        case .missingAudio:
            "This model turns speech into text. Attach an audio file first."
        case .missingText:
            "This model reads text aloud. Type what it should say first."
        case .missingInstruction:
            "This model needs a description of the voice. Add one under Style first."
        case .missingReference:
            "This model speaks in a voice it copies from a recording. Add a voice first."
        case .missingReferenceText:
            "This model needs the words spoken in the voice recording. Add them to the voice."
        case .unreadableReference:
            "The voice recording could not be read. Try a WAV, MP3 or M4A file."
        case .tooManySpeakers(let most):
            "This model speaks in at most \(most) voices at once. Use fewer speakers in the text."
        case .missingSpeakerVoice(let speaker):
            "\(speaker) has no voice yet. Give each speaker a voice under Speakers first."
        case .scriptStopped(let finished, let total, let detail):
            Self.join(
                "Only the first \(finished) of \(total) lines were read; the clip holds those. Line \(finished + 1) could not be read.",
                detail
            )
        case .unknownVoice(let voice):
            "This model has no voice called \"\(voice)\". Pick another voice."
        case .unreadableAudio:
            "The attached audio could not be read. Try a WAV, MP3 or M4A file."
        case .helperUnavailable(let reason):
            "The engine could not be started: \(reason)"
        case .modelLoadFailed(let detail):
            Self.join("The model could not be loaded. Its files may be damaged or unsupported.", detail)
        case .outOfMemory:
            "This Mac ran out of memory. Try a smaller image size, a smaller quantization, or close other apps."
        case .crashed(let detail):
            Self.join("The engine stopped unexpectedly.", detail)
        case .generationFailed(let detail):
            Self.join("The model could not finish this request.", detail)
        case .invalidOutput:
            "The engine returned data Kiln could not read."
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
