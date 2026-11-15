import Foundation

extension ModelRecipe {
    /// How a model that speaks is run.
    public struct SpeechDefaults: Codable, Sendable, Equatable {
        /// The engine's name for the kind of model, such as `pocket_tts`.
        public var family: String
        /// Voices built into the model file. When absent, the voices are the
        /// recipe's `voice` files.
        public var voices: [String]?
        /// The voice used until the user picks one. The first voice when absent.
        public var voice: String?
        /// Whether the model takes a description of the voice or the delivery,
        /// such as "Very happy." Absent for a model that takes none.
        public var instruction: Instruction?
        /// The fixed words the model takes instead of a free description, in
        /// groups of which one word may be chosen, such as an age or a pitch.
        public var styles: [StyleGroup]?
        /// Marks the model understands inside the text, such as `[laughter]`,
        /// written as they are typed.
        public var tags: [String]?

        public init(
            family: String, voices: [String]? = nil, voice: String? = nil, instruction: Instruction? = nil,
            styles: [StyleGroup]? = nil, tags: [String]? = nil
        ) {
            self.family = family
            self.voices = voices
            self.voice = voice
            self.instruction = instruction
            self.styles = styles
            self.tags = tags
        }

        /// What the model is told for a set of chosen style words: the ones it
        /// knows, at most one per group, in the recipe's order. Nil when none is left.
        public func instruction(choosing chosen: [String]) -> String? {
            let words = (styles ?? []).compactMap { group in group.options.first(where: chosen.contains) }
            return words.isEmpty ? nil : words.joined(separator: ", ")
        }
    }

    /// One trait of a voice and the words the model knows for it.
    public struct StyleGroup: Codable, Sendable, Equatable {
        /// What the words describe, such as "Age".
        public var name: String
        /// The words as the engine takes them, such as "young adult".
        public var options: [String]

        public init(name: String, options: [String]) {
            self.name = name
            self.options = options
        }
    }

    /// How a model treats a description of the voice or the delivery.
    public enum Instruction: String, Codable, Sendable {
        /// The model works without one.
        case optional
        /// The model cannot speak without one.
        case required
    }

    /// Names of the voices the model can speak in, in the order to offer them.
    public var voices: [String] {
        if let voices = speech?.voices { return voices }
        return components.filter { $0.role == .voice }.map(\.voiceName)
    }

    /// The voice to use when the user has not picked one.
    public var defaultVoice: String? {
        let voices = voices
        if let voice = speech?.voice, voices.contains(voice) { return voice }
        return voices.first
    }
}

extension ModelRecipe.Component {
    /// A voice file's name without its folder and extension, which is what the
    /// engine knows the voice by.
    public var voiceName: String {
        URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
    }
}
