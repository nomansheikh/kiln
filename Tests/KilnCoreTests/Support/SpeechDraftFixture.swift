import Foundation
@testable import KilnCore

/// Models of each kind the Speech composer meets, and voices of the user's own
/// that exist only as records: a draft never opens a recording.
struct SpeechDraftFixture {
    let store = VoiceStore(directory: URL(fileURLWithPath: "/voices"))
    let anna = SavedVoice(
        id: UUID(), name: "Anna", transcript: "Hello there.", createdAt: Date(timeIntervalSince1970: 0), design: nil, fileName: "anna.wav"
    )
    /// A voice saved without the words spoken in it.
    let wordless = SavedVoice(
        id: UUID(), name: "Ben", transcript: "", createdAt: Date(timeIntervalSince1970: 0), design: nil, fileName: "ben.wav"
    )

    /// A model with the voices "alba" and "george", of which "george" is the default.
    var named: ModelRecipe {
        speech(.init(family: "pocket_tts", voices: ["alba", "george"], voice: "george"))
    }

    /// A model without voices of its own. `text` says whether it needs the words spoken in a recording.
    func copying(_ reference: ModelRecipe.Support = .required, text: ModelRecipe.Support? = nil) -> ModelRecipe {
        speech(.init(family: "omnivoice", reference: reference, referenceText: text), id: "copying")
    }

    /// A model that takes a written description of the voice.
    func described(_ instruction: ModelRecipe.Support) -> ModelRecipe {
        speech(.init(family: "qwen3_tts", voices: ["alba"], instruction: instruction), id: "described")
    }

    /// A model that takes fixed words: one for the age and one for the pitch.
    var styled: ModelRecipe {
        let styles: [ModelRecipe.StyleGroup] = [
            .init(name: "Age", options: ["child", "elderly"]), .init(name: "Pitch", options: ["low pitch", "high pitch"]),
        ]
        return speech(.init(family: "omnivoice", styles: styles, reference: .optional), id: "styled")
    }

    /// A model that reads a whole script itself, with up to two speakers.
    var scripted: ModelRecipe {
        speech(.init(family: "vibevoice", reference: .optional, speakers: .init(max: 2, line: "Speaker {n}: {text}")), id: "scripted")
    }

    func draft(_ text: String = "Hello.", recipe: ModelRecipe?, voice: String? = nil, savedVoiceID: UUID? = nil) -> SpeechDraft {
        SpeechDraft(
            text: text, recipe: recipe, voice: voice, savedVoiceID: savedVoiceID,
            savedVoices: [anna, wordless], voiceStore: store
        )
    }

    func speech(_ speech: ModelRecipe.SpeechDefaults, id: String = "named", languages: [String]? = nil) -> ModelRecipe {
        var recipe = ModelRecipe(
            id: id, name: id, engine: AudioCppEngine.engineID,
            components: [.init(role: .model, repo: "owner/name", file: "\(id).gguf")],
            output: .audio, defaults: nil, speech: speech
        )
        recipe.languages = languages
        return recipe
    }
}
