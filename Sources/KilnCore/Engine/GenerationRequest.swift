import Foundation

/// One prompt to run: what every kind of model takes, plus the settings of its kind.
public struct GenerationRequest: Codable, Sendable, Equatable {
    public var prompt: String
    /// A file to work from, such as an image to rework.
    public var attachment: URL?
    /// Settings for an image model. Nil for other kinds.
    public var image: ImageSettings?

    public init(prompt: String, attachment: URL? = nil, image: ImageSettings? = nil) {
        self.prompt = prompt
        self.attachment = attachment
        self.image = image
    }

    /// An image request using the recipe's recommended settings.
    public init(prompt: String, negativePrompt: String = "", defaults: ModelRecipe.ImageDefaults, seed: Int64) {
        self.init(prompt: prompt, image: ImageSettings(negativePrompt: negativePrompt, defaults: defaults, seed: seed))
    }

    public static func randomSeed() -> Int64 {
        Int64.random(in: 0...Int64(UInt32.max))
    }

    enum CodingKeys: String, CodingKey {
        case prompt, attachment, image
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(attachment, forKey: .attachment)
        try container.encodeIfPresent(image, forKey: .image)
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
