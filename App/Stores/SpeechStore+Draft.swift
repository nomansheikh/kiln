import Foundation
import KilnCore

/// The composer's fields as a `SpeechDraft`, which decides what is sent and
/// whether it can be. The decisions live in KilnCore, where they are tested;
/// the store holds the fields so that views can observe them.
extension SpeechStore {
    var draft: SpeechDraft {
        SpeechDraft(
            text: text, recipe: selectedRecipe, voice: voice, savedVoiceID: savedVoiceID, language: language,
            instruction: instruction, styleWords: styleWords, cast: cast,
            savedVoices: voices.voices, voiceStore: voices.store
        )
    }

    /// Takes over what a draft changed: switching the model or putting a clip back.
    func apply(_ draft: SpeechDraft) {
        text = draft.text
        setRecipe(draft.recipe)
        voice = draft.voice
        savedVoiceID = draft.savedVoiceID
        language = draft.language
        instruction = draft.instruction
        styleWords = draft.styleWords
        cast = draft.cast
    }

    // MARK: - The voice and the style

    /// True when the selected model can copy a voice.
    var copiesVoices: Bool { draft.copiesVoices }

    /// The chosen voice of the user's own, when the selected model can use it.
    var savedVoice: SavedVoice? { draft.savedVoice }

    /// Why the model cannot speak yet, as far as its voice goes. Nil when it can.
    var voiceProblem: String? { draft.voiceProblem }

    /// The instruction as the selected model gets it: nil when it takes none or none is written.
    var sentInstruction: String? { draft.sentInstruction }

    /// True when the selected model cannot speak until a style is described.
    var needsInstruction: Bool { draft.needsInstruction }

    // MARK: - Scripts

    /// How the selected model reads several speakers itself. Nil when it speaks in one voice at a time.
    var speakerRule: ModelRecipe.Speakers? { draft.speakerRule }

    var script: SpeechScript { draft.script }

    /// True when the text is read as a script: it has several speakers, or the model reads nothing else.
    var isScript: Bool { draft.isScript }

    /// The voice a speaker is read in: the one chosen, or the one the model's voices give them in turn.
    func castVoice(of speaker: String) -> CastVoice? { draft.castVoice(of: speaker) }

    /// Why the model cannot read the script. Nil when it can.
    var speakerProblem: String? { draft.speakerProblem }

    /// The name a new speaker gets: the first "Speaker N" the text does not use.
    var nextSpeakerName: String { draft.nextSpeakerName }
}
