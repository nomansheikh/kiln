import Foundation

/// Who reads which part of a script: the voice each speaker is given, and
/// the script as separate requests for a model that speaks in one voice at a time.
public enum SpeechCast {
    /// The voice of each speaker, by `SpeechScript.key` of their name. A speaker
    /// keeps the voice chosen for them when the model has it, or the model's voice
    /// of the same name. The others take the
    /// model's named voices in turn, so that no two sound alike while there are
    /// voices left. A speaker of a model without named voices has none until one is chosen.
    public static func voices(for script: SpeechScript, recipe: ModelRecipe, settings: SpeechSettings?) -> [String: CastVoice] {
        var chosen: [String: CastVoice] = [:]
        for (name, voice) in settings?.cast ?? [:] {
            if voice.reference != nil, recipe.speech?.reference != nil {
                chosen[SpeechScript.key(name)] = CastVoice(reference: voice.reference)
            } else if let named = voice.voice, recipe.voices.contains(named) {
                chosen[SpeechScript.key(name)] = CastVoice(voice: named)
            }
        }
        // A speaker called what one of the model's voices is called gets that voice.
        for speaker in script.speakers where chosen[SpeechScript.key(speaker)] == nil {
            if let namesake = recipe.voices.first(where: { SpeechScript.key($0) == SpeechScript.key(speaker) }),
               !chosen.values.contains(where: { $0.voice == namesake }) {
                chosen[SpeechScript.key(speaker)] = CastVoice(voice: namesake)
            }
        }
        // The voice picked for the whole text goes first.
        var free = recipe.voices.filter { named in !chosen.values.contains { $0.voice == named } }
        if let first = settings?.voice ?? recipe.defaultVoice, let index = free.firstIndex(of: first) {
            free.insert(free.remove(at: index), at: 0)
        }
        var next = 0
        for (place, speaker) in script.speakers.enumerated() {
            let key = SpeechScript.key(speaker)
            guard chosen[key] == nil else { continue }
            if place == 0, let only = settings?.reference, recipe.speech?.reference != nil {
                // A recording picked for the whole text is the first speaker's.
                chosen[key] = CastVoice(reference: only)
            } else if !recipe.voices.isEmpty {
                let pool = free.isEmpty ? recipe.voices : free
                chosen[key] = CastVoice(voice: pool[next % pool.count])
                next += 1
            }
        }
        return chosen
    }

    /// True when the model reads the whole script itself, each speaker in a voice of their own.
    public static func readsScripts(_ recipe: ModelRecipe) -> Bool {
        recipe.speech?.speakers != nil
    }

    /// The speakers that cannot be read yet: a model that speaks in one voice at
    /// a time would make up a different voice for every line of theirs.
    public static func speakersWithoutVoice(in script: SpeechScript, recipe: ModelRecipe, settings: SpeechSettings?) -> [String] {
        guard script.isDialogue, !readsScripts(recipe) else { return [] }
        let voices = voices(for: script, recipe: recipe, settings: settings)
        return script.speakers.filter { voices[SpeechScript.key($0)] == nil }
    }

    /// The script as one request per turn, each in its speaker's voice, for a
    /// model that speaks in one voice at a time. Nil when the request goes to
    /// the model as it is: the text has one speaker, or the model reads scripts.
    public static func turns(of request: GenerationRequest, recipe: ModelRecipe) throws(EngineError) -> [GenerationRequest]? {
        guard recipe.speech != nil, !readsScripts(recipe) else { return nil }
        let script = SpeechScript(request.prompt)
        guard script.isDialogue else { return nil }
        if let speaker = speakersWithoutVoice(in: script, recipe: recipe, settings: request.speech).first {
            throw .missingSpeakerVoice(speaker)
        }
        let voices = voices(for: script, recipe: recipe, settings: request.speech)
        let whole = request.speech?.instruction
        return script.turns.filter { !$0.text.isEmpty }.map { turn in
            let voice = voices[SpeechScript.key(turn.speaker)]
            // A model with fixed style words takes the turn's note with the words
            // for the whole text; any other is told the note in place of them.
            let instruction = recipe.speech?.styles != nil
                ? [whole, turn.note].compactMap { $0 }.joined(separator: ", ")
                : turn.note ?? whole
            return GenerationRequest(
                prompt: turn.text,
                speech: SpeechSettings(voice: voice?.voice, instruction: instruction, reference: voice?.reference),
                language: request.language
            )
        }
    }
}
