import Foundation

/// Changing a draft as a whole: switching the model, and putting a clip back.
extension SpeechDraft {
    /// Switches to another model, keeping what the new one can use.
    public mutating func select(_ recipe: ModelRecipe?) {
        self.recipe = recipe
        // Keep the chosen voice when the new model has it too.
        if let recipe, voice.map({ !recipe.voices.contains($0) }) ?? true {
            voice = recipe.defaultVoice
        }
        // A language the new model does not offer goes back to "Auto".
        if let language, recipe?.languages?.contains(language) != true {
            self.language = nil
        }
    }

    /// Puts a clip's text, voices and style back, for the model it was made with.
    public mutating func reuse(_ request: GenerationRequest, madeWith recipe: ModelRecipe) {
        text = request.prompt
        select(recipe)
        let settings = request.speech

        // The voice: the user's own if it still exists, else the model's.
        if let file = settings?.reference?.file, let saved = savedVoice(recordedIn: file) {
            savedVoiceID = saved.id
        } else if let named = settings?.voice, recipe.voices.contains(named) {
            voice = named
            savedVoiceID = nil
        }

        // A script's speakers, where their voices still exist.
        for (speaker, chosen) in settings?.cast ?? [:] {
            if let named = chosen.voice {
                cast[SpeechScript.key(speaker)] = .named(named)
            } else if let file = chosen.reference?.file, let saved = savedVoice(recordedIn: file) {
                cast[SpeechScript.key(speaker)] = .saved(saved.id)
            }
        }

        // The style: its words for a model with fixed ones, its description otherwise.
        if recipe.speech?.styles != nil {
            styleWords = (settings?.instruction ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else if recipe.speech?.instruction != nil {
            instruction = settings?.instruction ?? ""
        }
    }
}
