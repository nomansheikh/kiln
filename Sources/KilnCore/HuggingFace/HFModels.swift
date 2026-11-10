import Foundation

public struct HFModelSummary: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let likes: Int
    public let downloads: Int
    public let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id, likes, downloads, tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        likes = try container.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        downloads = try container.decodeIfPresent(Int.self, forKey: .downloads) ?? 0
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public var author: String {
        id.split(separator: "/").first.map(String.init) ?? ""
    }

    public var license: String? {
        tags.first { $0.hasPrefix("license:") }.map { String($0.dropFirst("license:".count)) }
    }
}

public struct HFModelInfo: Decodable, Sendable, Equatable {
    public let id: String
    /// Commit the file list was read at.
    public let revision: String?
    public let isGated: Bool
    public let tags: [String]
    public let files: [HFFile]

    enum CodingKeys: String, CodingKey {
        case id, sha, gated, tags, siblings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decodeIfPresent(String.self, forKey: .sha)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        files = try container.decodeIfPresent([HFFile].self, forKey: .siblings) ?? []
        // `gated` is `false` for open repos and "auto" or "manual" for gated ones.
        if let flag = try? container.decode(Bool.self, forKey: .gated) {
            isGated = flag
        } else {
            isGated = (try? container.decode(String.self, forKey: .gated)) != nil
        }
    }

    public var license: String? {
        tags.first { $0.hasPrefix("license:") }.map { String($0.dropFirst("license:".count)) }
    }

    /// Weight files a user could pick to run, largest first.
    public var weightFiles: [HFFile] {
        files.filter(\.isWeights).sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
    }
}

public struct HFFile: Decodable, Sendable, Equatable, Identifiable {
    public let path: String
    public let sizeBytes: Int64?
    public let sha256: String?

    public var id: String { path }

    enum CodingKeys: String, CodingKey {
        case rfilename, size, lfs
    }

    struct LFS: Decodable {
        let sha256: String?
    }

    public init(path: String, sizeBytes: Int64?, sha256: String?) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .rfilename)
        sizeBytes = try container.decodeIfPresent(Int64.self, forKey: .size)
        sha256 = try container.decodeIfPresent(LFS.self, forKey: .lfs)?.sha256
    }

    public var name: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    public var isWeights: Bool {
        let lowered = path.lowercased()
        return lowered.hasSuffix(".gguf") || lowered.hasSuffix(".safetensors")
    }

    /// Vision projector for image editing; not needed for text-to-image.
    public var isVisionProjector: Bool {
        name.lowercased().hasPrefix("mmproj")
    }

    /// Whether the file is plausibly a whole model in one file, the only kind that runs
    /// without a recipe. This is a guess from the name: a `.safetensors` file at the top
    /// of the repo, large enough to hold a model, whose name does not mark it as one
    /// part (a VAE, text encoder, LoRA and so on). GGUF files are published per part.
    public var looksLikeStandaloneCheckpoint: Bool {
        let lowered = path.lowercased()
        guard lowered.hasSuffix(".safetensors"), !path.contains("/") else { return false }
        if let sizeBytes, sizeBytes < 1_500_000_000 { return false }
        let partMarkers = ["vae", "clip", "t5", "encoder", "lora", "mmproj", "unet", "transformer", "controlnet", "adapter", "refiner"]
        return !partMarkers.contains { lowered.contains($0) }
    }

    /// Quantization label parsed from the file name, e.g. `Q8_0`, `Q4_K_M`, `BF16`.
    public var quantization: String? {
        let stem = name.split(separator: ".").dropLast().joined(separator: ".")
        let pattern = /(?i)(?:^|[-_.])((?:I?Q\d+(?:_[A-Z0-9]+)*)|BF16|F16|F32|FP16|FP32|INT8)(?=$|[-_.])/
        guard let match = stem.matches(of: pattern).last else { return nil }
        return String(match.1).uppercased()
    }
}
