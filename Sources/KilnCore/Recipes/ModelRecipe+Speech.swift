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

        public init(family: String, voices: [String]? = nil, voice: String? = nil) {
            self.family = family
            self.voices = voices
            self.voice = voice
        }
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
