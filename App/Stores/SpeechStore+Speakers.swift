import Foundation
import KilnCore

/// A script: a text with several speakers, each read in a voice of their own.
/// A model that reads scripts gets the whole text; any other reads it turn by turn.
extension SpeechStore {
    /// The voice chosen for a speaker: one of the model's, or one of the user's own.
    enum CastChoice: Equatable {
        case named(String)
        case saved(UUID)
    }

    /// How the selected model reads several speakers itself. Nil when it speaks in one voice at a time.
    var speakerRule: ModelRecipe.Speakers? {
        selectedRecipe?.speech?.speakers
    }

    var script: SpeechScript {
        SpeechScript(text)
    }

    /// True when the text is read as a script: it has several speakers, or the model reads nothing else.
    var isScript: Bool {
        selectedRecipe != nil && (speakerRule != nil || script.isDialogue)
    }

    /// The voices chosen for the speakers in the text, as the engine takes them.
    var sentCast: [String: CastVoice]? {
        var sent: [String: CastVoice] = [:]
        for speaker in script.speakers {
            switch cast[SpeechScript.key(speaker)] {
            case .named(let voice): sent[speaker] = CastVoice(voice: voice)
            case .saved(let id):
                if let saved = voices.voices.first(where: { $0.id == id }) {
                    sent[speaker] = CastVoice(reference: saved.reference(in: voices.store))
                }
            case nil: break
            }
        }
        return sent.isEmpty ? nil : sent
    }

    /// What a script is sent with.
    var scriptSettings: SpeechSettings {
        SpeechSettings(voice: voice, instruction: sentInstruction, cast: sentCast)
    }

    /// The voice a speaker is read in: the one chosen, or the one the model's voices give them in turn.
    func castVoice(of speaker: String) -> CastVoice? {
        guard let recipe = selectedRecipe else { return nil }
        return SpeechCast.voices(for: script, recipe: recipe, settings: scriptSettings)[SpeechScript.key(speaker)]
    }

    func choose(_ choice: CastChoice?, for speaker: String) {
        cast[SpeechScript.key(speaker)] = choice
    }

    /// Opens the sheet for adding or designing a voice, which then becomes that speaker's.
    func addVoice(for speaker: String, designing: Bool) {
        editedVoiceID = nil
        if designing { isDesigningVoice = true } else { isAddingVoice = true }
        pendingSpeaker = speaker
    }

    /// Why the model cannot read the script. Nil when it can.
    var speakerProblem: String? {
        guard isScript, let recipe = selectedRecipe else { return nil }
        if let rule = speakerRule, script.speakers.count > rule.max {
            return "This model speaks in at most \(rule.max) voices at once, and the text has \(script.speakers.count) speakers."
        }
        let waiting = SpeechCast.speakersWithoutVoice(in: script, recipe: recipe, settings: scriptSettings)
        if !waiting.isEmpty {
            return "\(waiting.joined(separator: " and ")) \(waiting.count == 1 ? "has" : "have") no voice yet. Choose one under Speakers."
        }
        if recipe.speech?.referenceText == .required, speakerRule == nil,
           let silent = sentCast?.values.compactMap(\.reference).first(where: { $0.transcript == nil }) {
            return "This model needs the words spoken in \u{201C}\(silent.name ?? "the voice")\u{201D} before it can copy the voice."
        }
        return nil
    }

    /// The name a new speaker gets: the first "Speaker N" the text does not use.
    var nextSpeakerName: String {
        let used = Set(script.speakers.map(SpeechScript.key))
        let number = (1...).first { !used.contains("speaker \($0)") } ?? 1
        return "Speaker \(number)"
    }

    /// Gives a clip's speakers their voices back, where those still exist.
    func restoreCast(of settings: SpeechSettings?) {
        for (speaker, voice) in settings?.cast ?? [:] {
            if let named = voice.voice {
                choose(.named(named), for: speaker)
            } else if let file = voice.reference?.file.lastPathComponent,
                      let saved = voices.voices.first(where: { voices.store.recording(of: $0).lastPathComponent == file }) {
                choose(.saved(saved.id), for: speaker)
            }
        }
    }
}
