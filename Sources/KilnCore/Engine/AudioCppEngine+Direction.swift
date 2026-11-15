import Foundation

/// What a request asks of a model beyond its text, checked against what the
/// recipe says the model takes.
extension AudioCppEngine {
    struct Direction: Equatable {
        /// A voice the model knows by name. Nil when a recording takes its place.
        var voice: String?
        /// A recording of the voice to speak in.
        var reference: URL?
        /// Settings by the names audio.cpp gives them.
        var options: [String: String] = [:]
    }

    static func direction(for request: GenerationRequest, recipe: ModelRecipe) throws(EngineError) -> Direction {
        let speech = recipe.speech
        var direction = Direction()

        // A recording goes only to a model that can copy a voice.
        if let reference = request.speech?.reference, speech?.reference != nil {
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
}
