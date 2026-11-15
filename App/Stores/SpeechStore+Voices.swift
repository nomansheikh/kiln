import Foundation
import KilnCore

/// Speaking in one of the user's own voices, for a model that can copy a
/// voice from a recording.
extension SpeechStore {
    /// True when the selected model can copy a voice.
    var copiesVoices: Bool {
        selectedRecipe?.speech?.reference != nil
    }

    /// The chosen voice of the user's own, when the selected model can use it.
    var savedVoice: SavedVoice? {
        guard copiesVoices, let savedVoiceID else { return nil }
        return voices.voices.first { $0.id == savedVoiceID }
    }

    /// The recording the selected model is given, if any.
    var sentReference: VoiceReference? {
        savedVoice?.reference(in: voices.store)
    }

    /// Why the model cannot speak yet, as far as its voice goes. Nil when it can.
    var voiceProblem: String? {
        // A script's speakers have voices of their own. See `speakerProblem`.
        guard let speech = selectedRecipe?.speech, !isScript else { return nil }
        if let savedVoice {
            return speech.referenceText == .required && savedVoice.transcript.isEmpty
                ? "This model needs the words spoken in \u{201C}\(savedVoice.name)\u{201D} before it can copy the voice." : nil
        }
        return speech.reference == .required ? "This model speaks in a voice it copies. Add a voice first." : nil
    }

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

    /// Puts a clip's voice back: the user's own if it still exists, else the model's.
    func restoreVoice(of settings: SpeechSettings?, for recipe: ModelRecipe) {
        if let file = settings?.reference?.file.lastPathComponent,
           let saved = voices.voices.first(where: { voices.store.recording(of: $0).lastPathComponent == file }) {
            savedVoiceID = saved.id
        } else if let voice = settings?.voice, recipe.voices.contains(voice) {
            self.voice = voice
            savedVoiceID = nil
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
