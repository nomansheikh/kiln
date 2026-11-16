import Foundation

/// What the Speech composer holds, and what follows from it: what the model
/// is sent, whether sending is possible, and if not, why.
///
/// It is a plain value so that these decisions can be tested. The app keeps
/// the same fields as observable state and asks a draft built from them.
public struct SpeechDraft: Sendable {
    /// The voice chosen for a speaker of a script: one of the model's, or one of the user's own.
    public enum CastChoice: Sendable, Equatable {
        case named(String)
        case saved(UUID)
    }

    public var text: String
    /// The selected model. Nil when no voice model is installed.
    public var recipe: ModelRecipe?
    /// The model's voice to speak in, by name.
    public var voice: String?
    /// The chosen voice of the user's own, which takes the place of `voice`.
    public var savedVoiceID: UUID?
    /// Code of the language to speak in. Nil lets the model decide.
    public var language: String?
    /// A description of the voice or the delivery, for a model that takes one.
    public var instruction: String
    /// The words chosen for a model that takes fixed style words instead.
    public var styleWords: [String]
    /// The voices chosen for the speakers of a script, by `SpeechScript.key` of their names.
    public var cast: [String: CastChoice]
    /// The user's own voices, and the folder their recordings are in.
    public var savedVoices: [SavedVoice]
    public var voiceStore: VoiceStore

    public init(
        text: String = "", recipe: ModelRecipe? = nil, voice: String? = nil, savedVoiceID: UUID? = nil,
        language: String? = nil, instruction: String = "", styleWords: [String] = [], cast: [String: CastChoice] = [:],
        savedVoices: [SavedVoice] = [], voiceStore: VoiceStore
    ) {
        self.text = text
        self.recipe = recipe
        self.voice = voice
        self.savedVoiceID = savedVoiceID
        self.language = language
        self.instruction = instruction
        self.styleWords = styleWords
        self.cast = cast
        self.savedVoices = savedVoices
        self.voiceStore = voiceStore
    }

    // MARK: - The model

    /// True when the selected model can copy a voice from a recording.
    public var copiesVoices: Bool {
        recipe?.speech?.reference != nil
    }

    /// How the selected model reads several speakers itself. Nil when it speaks in one voice at a time.
    public var speakerRule: ModelRecipe.Speakers? {
        recipe?.speech?.speakers
    }

    // MARK: - The text

    public var script: SpeechScript {
        SpeechScript(text)
    }

    /// True when the text is read as a script: it has several speakers, or the model reads nothing else.
    public var isScript: Bool {
        recipe != nil && (speakerRule != nil || script.isDialogue)
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - The voice and the style

    /// The chosen voice of the user's own, when the selected model can use it.
    public var savedVoice: SavedVoice? {
        guard copiesVoices, let savedVoiceID else { return nil }
        return savedVoices.first { $0.id == savedVoiceID }
    }

    /// The recording the selected model is given for a text with one voice, if any.
    public var reference: VoiceReference? {
        savedVoice?.reference(in: voiceStore)
    }

    /// The instruction as the selected model gets it: nil when it takes none or none is written.
    public var sentInstruction: String? {
        if let speech = recipe?.speech, speech.styles != nil {
            return speech.instruction(choosing: styleWords)
        }
        let written = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return recipe?.speech?.instruction == nil || written.isEmpty ? nil : written
    }

    /// True when the selected model cannot speak until a style is described.
    public var needsInstruction: Bool {
        recipe?.speech?.instruction == .required && sentInstruction == nil
    }

    /// The saved voice whose recording is the given file, for putting a clip's voice back.
    func savedVoice(recordedIn file: URL) -> SavedVoice? {
        savedVoices.first { voiceStore.recording(of: $0).lastPathComponent == file.lastPathComponent }
    }
}
