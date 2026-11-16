import Foundation

/// What a draft sends, and what stands in the way of sending it.
extension SpeechDraft {
    // MARK: - Scripts

    /// The voices chosen for the speakers in the text, as the engine takes them.
    public var sentCast: [String: CastVoice]? {
        var sent: [String: CastVoice] = [:]
        for speaker in script.speakers {
            switch cast[SpeechScript.key(speaker)] {
            case .named(let voice): sent[speaker] = CastVoice(voice: voice)
            case .saved(let id):
                if let saved = savedVoices.first(where: { $0.id == id }) {
                    sent[speaker] = CastVoice(reference: saved.reference(in: voiceStore))
                }
            case nil: break
            }
        }
        return sent.isEmpty ? nil : sent
    }

    /// The voice a speaker is read in: the one chosen, or the one the model's voices give them in turn.
    public func castVoice(of speaker: String) -> CastVoice? {
        guard let recipe else { return nil }
        return SpeechCast.voices(for: script, recipe: recipe, settings: scriptSettings)[SpeechScript.key(speaker)]
    }

    /// The name a new speaker gets: the first "Speaker N" the text does not use.
    public var nextSpeakerName: String {
        let used = Set(script.speakers.map(SpeechScript.key))
        let number = (1...).first { !used.contains("speaker \($0)") } ?? 1
        return "Speaker \(number)"
    }

    var scriptSettings: SpeechSettings {
        SpeechSettings(voice: voice, instruction: sentInstruction, cast: sentCast)
    }

    // MARK: - The request

    /// What the model is sent with: a script's speakers each have a voice, any other text has one.
    public var settings: SpeechSettings {
        isScript
            ? scriptSettings
            : SpeechSettings(voice: reference == nil ? voice : nil, instruction: sentInstruction, reference: reference)
    }

    public var request: GenerationRequest {
        GenerationRequest(prompt: trimmedText, speech: settings, language: language)
    }

    // MARK: - What stands in the way

    /// Why the model cannot speak yet, as far as its one voice goes. Nil when it can, and for a script.
    public var voiceProblem: String? {
        // A script's speakers have voices of their own. See `speakerProblem`.
        guard let speech = recipe?.speech, !isScript else { return nil }
        if let savedVoice {
            return speech.referenceText == .required && savedVoice.transcript.isEmpty
                ? "This model needs the words spoken in \u{201C}\(savedVoice.name)\u{201D} before it can copy the voice." : nil
        }
        return speech.reference == .required ? "This model speaks in a voice it copies. Add a voice first." : nil
    }

    /// Why the model cannot read the script. Nil when it can, and for a text that is not one.
    public var speakerProblem: String? {
        guard isScript, let recipe else { return nil }
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

    /// True when the draft can be sent, as far as the draft itself goes: there is
    /// a model, something to say, and nothing missing. Whether the engine is free
    /// is the app's to know.
    public var canSend: Bool {
        recipe != nil && !needsInstruction && voiceProblem == nil && speakerProblem == nil && !trimmedText.isEmpty
    }
}
