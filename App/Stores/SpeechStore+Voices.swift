import Foundation
import KilnCore

/// Speaking in one of the user's own voices, for a model that can copy a
/// voice from a recording.
extension SpeechStore {
    /// Saves a recording as a voice and selects it, for the speaker it was added for if there is one.
    func addVoice(recording: URL, name: String, transcript: String) throws {
        let voice = try voices.add(recording: recording, name: name, transcript: transcript)
        if let pendingSpeaker {
            choose(.saved(voice.id), for: pendingSpeaker)
        } else {
            savedVoiceID = voice.id
        }
    }

    /// Opens the sheet to change a voice's name or words.
    func edit(_ voice: SavedVoice) {
        editedVoiceID = voice.id
        isAddingVoice = true
    }

    /// The voice the open sheet is changing, or nil when it is adding one.
    var editedVoice: SavedVoice? {
        voices.voices.first { $0.id == editedVoiceID }
    }

    func updateVoice(_ voice: SavedVoice, name: String, transcript: String) throws {
        var changed = voice
        changed.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        changed.transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        try voices.update(changed)
    }

    /// The installed speech-to-text model that writes down a recording's words, if there is one.
    var transcriber: ModelRecipe? {
        library.installedRecipes.first { $0.task == .speechToText }
    }

    /// Writes down the words in the part of a recording that is used, with an
    /// installed speech-to-text model.
    func transcribe(_ recording: URL, language: String?) async throws -> String {
        guard let recipe = transcriber else { throw VoiceTranscriptionError.noModel }
        guard !isUsingEngine, !isEngineBusyElsewhere() else { throw VoiceTranscriptionError.busy }
        let clip = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-voice-\(UUID().uuidString).wav")
        try AudioSamples.referenceClip(of: recording).wavData().write(to: clip)
        defer { try? FileManager.default.removeItem(at: clip) }
        for try await event in engine.generate(recipe: recipe, request: GenerationRequest(prompt: "", attachment: clip, language: language)) {
            if case .finished(.text(let words)) = event {
                return words.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    func deleteVoice(_ voice: SavedVoice) {
        if savedVoiceID == voice.id { savedVoiceID = nil }
        do {
            try voices.delete(voice)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum VoiceTranscriptionError: LocalizedError {
    case noModel
    case busy

    var errorDescription: String? {
        switch self {
        case .noModel: "Install a speech-to-text model, such as Whisper, to have the words written for you."
        case .busy: "Another model is working. Wait for it to finish, then try again."
        }
    }
}
