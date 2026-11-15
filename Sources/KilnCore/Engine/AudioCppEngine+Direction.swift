import Foundation

/// What a request asks of a model beyond its text, checked against what the
/// recipe says the model takes.
extension AudioCppEngine {
    struct Direction: Equatable {
        /// A voice the model knows by name. Nil when a recording takes its place.
        var voice: String?
        /// A recording of the voice to speak in.
        var reference: URL?
        /// The text as the model reads it.
        var text = ""
        /// Recordings of the voices of a text with several speakers, in the
        /// order the model numbers them.
        var samples: [URL] = []
        /// Settings by the names audio.cpp gives them.
        var options: [String: String] = [:]
    }

    /// - Parameter text: What to say, when it is not the request's prompt as written.
    static func direction(
        for request: GenerationRequest, text: String? = nil, recipe: ModelRecipe
    ) throws(EngineError) -> Direction {
        let speech = recipe.speech
        var direction = Direction()
        direction.text = text ?? request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if let speakers = speech?.speakers {
            try cast(SpeechScript(direction.text), as: speakers, request: request, recipe: recipe, into: &direction)
        } else if let reference = request.speech?.reference, speech?.reference != nil {
            direction.reference = reference.file
            let words = reference.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if speech?.referenceText != nil, !words.isEmpty {
                direction.options["reference_text"] = words
            } else if speech?.referenceText == .required {
                throw .missingReferenceText
            }
        } else if speech?.reference == .required {
            throw .missingReference
        } else {
            // Only a voice the recipe lists is passed on: some models load a voice
            // from a file named after it.
            direction.voice = request.speech?.voice ?? recipe.defaultVoice
            if let voice = direction.voice, !recipe.voices.contains(voice) { throw .unknownVoice(voice) }
        }

        // An instruction goes only to a model that takes one; the others refuse it.
        // A model with fixed style words gets only the words it knows.
        let written = request.speech?.instruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let instruction: String? = if speech?.styles != nil {
            speech?.instruction(choosing: written.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        } else {
            speech?.instruction == nil || written.isEmpty ? nil : written
        }
        if speech?.instruction == .required, instruction == nil { throw .missingInstruction }
        direction.options["instruct"] = instruction
        return direction
    }

    /// Writes a text with several speakers the way the model reads it, and
    /// lines up the recordings of their voices with the model's numbering.
    private static func cast(
        _ script: SpeechScript, as speakers: ModelRecipe.Speakers, request: GenerationRequest, recipe: ModelRecipe,
        into direction: inout Direction
    ) throws(EngineError) {
        guard script.speakers.count <= speakers.max else { throw .tooManySpeakers(speakers.max) }
        var voices: [String: VoiceReference] = [:]
        if recipe.speech?.reference != nil {
            for (name, voice) in SpeechCast.voices(for: script, recipe: recipe, settings: request.speech) {
                voices[name] = voice.reference
            }
        }
        // A model takes recordings for its first speakers only, so the speakers
        // with a recording are numbered before the ones without.
        let voiced = script.speakers.filter { voices[SpeechScript.key($0)] != nil }
        let order = voiced + script.speakers.filter { voices[SpeechScript.key($0)] == nil }
        direction.text = script.rendered(line: speakers.line, order: order)
        direction.samples = voiced.compactMap { voices[SpeechScript.key($0)]?.file }
    }
}
