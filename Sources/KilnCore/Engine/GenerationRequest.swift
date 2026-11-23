import Foundation

/// One prompt to run: what every kind of model takes, plus the settings of its kind.
public struct GenerationRequest: Codable, Sendable, Equatable {
    public var prompt: String
    /// A file to work from, such as an image to rework.
    public var attachment: URL?
    /// Settings for an image model. Nil for other kinds.
    public var image: ImageSettings?
    /// Settings for a model that speaks. Nil for other kinds.
    public var speech: SpeechSettings?
    /// Settings for a model that makes 3D objects. Nil for other kinds.
    public var mesh: MeshSettings?
    /// Code of the language to work in, such as `en`. Nil lets the model decide.
    public var language: String?

    public init(
        prompt: String, attachment: URL? = nil, image: ImageSettings? = nil, speech: SpeechSettings? = nil,
        mesh: MeshSettings? = nil, language: String? = nil
    ) {
        self.prompt = prompt
        self.attachment = attachment
        self.image = image
        self.speech = speech
        self.mesh = mesh
        self.language = language
    }

    /// The language to give the engine: the chosen one, if the recipe offers it.
    func language(for recipe: ModelRecipe) -> String? {
        language.flatMap { recipe.languages?.contains($0) == true ? $0 : nil }
    }

    /// An image request using the recipe's recommended settings.
    public init(prompt: String, negativePrompt: String = "", defaults: ModelRecipe.ImageDefaults, seed: Int64) {
        self.init(prompt: prompt, image: ImageSettings(negativePrompt: negativePrompt, defaults: defaults, seed: seed))
    }

    public static func randomSeed() -> Int64 {
        Int64.random(in: 0...Int64(UInt32.max))
    }

    enum CodingKeys: String, CodingKey {
        case prompt, attachment, image, speech, mesh, language
        /// Records written before requests had kinds kept the image settings at the
        /// top level and called the attachment `sourceImage`.
        case sourceImage, width
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try container.decode(String.self, forKey: .prompt)
        attachment = try container.decodeIfPresent(URL.self, forKey: .attachment)
            ?? container.decodeIfPresent(URL.self, forKey: .sourceImage)
        if container.contains(.image) {
            image = try container.decode(ImageSettings.self, forKey: .image)
        } else if container.contains(.width) {
            image = try ImageSettings(from: decoder)
        }
        speech = try container.decodeIfPresent(SpeechSettings.self, forKey: .speech)
        mesh = try container.decodeIfPresent(MeshSettings.self, forKey: .mesh)
        language = try container.decodeIfPresent(String.self, forKey: .language)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(attachment, forKey: .attachment)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(speech, forKey: .speech)
        try container.encodeIfPresent(mesh, forKey: .mesh)
        try container.encodeIfPresent(language, forKey: .language)
    }
}

/// Settings of one piece of generated speech.
public struct SpeechSettings: Codable, Sendable, Equatable {
    /// The voice to speak in, by the name the model knows it by.
    public var voice: String?
    /// A description of the voice or the delivery, for a model that takes one.
    public var instruction: String?
    /// A recording of the voice to speak in, for a model that can copy one.
    /// It takes the place of `voice`.
    public var reference: VoiceReference?
    /// The voices of the speakers of a script, by the name each is given in the text.
    public var cast: [String: CastVoice]?

    public init(
        voice: String? = nil, instruction: String? = nil, reference: VoiceReference? = nil,
        cast: [String: CastVoice]? = nil
    ) {
        self.voice = voice
        self.instruction = instruction
        self.reference = reference
        self.cast = cast
    }
}

/// The voice one speaker of a script is read in: one the model knows by name,
/// or a recording to copy.
public struct CastVoice: Codable, Sendable, Equatable {
    public var voice: String?
    public var reference: VoiceReference?

    public init(voice: String? = nil, reference: VoiceReference? = nil) {
        self.voice = voice
        self.reference = reference
    }
}

/// A recording of a voice for a model to copy.
public struct VoiceReference: Codable, Sendable, Equatable {
    /// An audio file of the voice speaking.
    public var file: URL
    /// The words spoken in it, which some models need.
    public var transcript: String?
    /// What the user calls the voice, for showing with a clip made in it.
    public var name: String?

    public init(file: URL, transcript: String? = nil, name: String? = nil) {
        self.file = file
        self.transcript = transcript
        self.name = name
    }
}

/// Settings of one image generation.
public struct ImageSettings: Codable, Sendable, Equatable {
    public var negativePrompt: String
    public var width: Int
    public var height: Int
    public var steps: Int
    public var cfg: Double
    public var sampler: String
    public var sigmas: [Double]?
    public var seed: Int64
    /// How far the result may move from the attached image: 0 keeps it, 1 ignores it.
    public var strength: Double?

    public init(
        negativePrompt: String = "",
        width: Int,
        height: Int,
        steps: Int,
        cfg: Double,
        sampler: String,
        sigmas: [Double]? = nil,
        seed: Int64,
        strength: Double? = nil
    ) {
        self.negativePrompt = negativePrompt
        self.width = width
        self.height = height
        self.steps = steps
        self.cfg = cfg
        self.sampler = sampler
        self.sigmas = sigmas
        self.seed = seed
        self.strength = strength
    }

    public init(negativePrompt: String = "", defaults: ModelRecipe.ImageDefaults, seed: Int64) {
        self.init(
            negativePrompt: negativePrompt,
            width: defaults.width,
            height: defaults.height,
            steps: defaults.steps,
            cfg: defaults.cfg,
            sampler: defaults.sampler,
            sigmas: defaults.sigmas,
            seed: seed
        )
    }
}
