import Foundation
import KilnCore

/// Making up a voice from a description, with a model that can, and keeping
/// it as one of the user's own voices so that any model which copies voices can use it.
extension SpeechStore {
    /// Installed models that can make up a voice: they take words about the
    /// voice, or cannot speak without a description of one.
    var designers: [ModelRecipe] {
        recipes.filter { $0.speech?.styles != nil || $0.speech?.instruction == .required }
    }

    /// Speaks a sample in a voice made up from a description.
    func designSample(with recipe: ModelRecipe, description: String, words: String) async throws -> GeneratedAudio {
        guard !isUsingEngine, !isEngineBusyElsewhere() else { throw VoiceTranscriptionError.busy }
        let request = GenerationRequest(prompt: words, speech: SpeechSettings(instruction: description), language: language)
        preparingPreview = Self.designPreview
        defer { preparingPreview = nil }
        for try await event in engine.generate(recipe: recipe, request: request) {
            if case .finished(.audio(let sound)) = event { return sound }
        }
        throw EngineError.invalidOutput
    }

    /// Keeps a designed sample as a voice, for the speaker it was made for if there is one.
    func saveDesigned(_ sound: GeneratedAudio, name: String, description: String, words: String) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-design-\(UUID().uuidString).wav")
        try sound.wavData().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let voice = try voices.add(recording: file, name: name, transcript: words, design: description)
        if let pendingSpeaker {
            choose(.saved(voice.id), for: pendingSpeaker)
        } else {
            savedVoiceID = voice.id
        }
    }

    /// Marks the engine as busy with a designed sample, as a voice sample does.
    static let designPreview = "\u{0}design"
}
