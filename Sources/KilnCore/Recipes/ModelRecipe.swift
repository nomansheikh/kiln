import Foundation

/// A runnable model: every file it needs plus the settings that make it work.
/// One recipe is one click in the UI.
public struct ModelRecipe: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var engine: String
    public var components: [Component]
    public var defaults: GenerationDefaults
    public var licenseNote: String?
    /// Smallest amount of system RAM the recipe is expected to run on.
    public var minMemoryGB: Double?
    /// Alternative sets of files for the same model, usually different quantizations.
    /// See `ModelRecipe+Variants.swift`.
    public var variants: [Variant]?
    /// The variant whose files were merged into `components`. Set by `resolved(_:)`, never stored.
    public var selectedVariantID: String?

    public init(
        id: String,
        name: String,
        engine: String,
        components: [Component],
        defaults: GenerationDefaults,
        licenseNote: String? = nil,
        minMemoryGB: Double? = nil,
        variants: [Variant]? = nil
    ) {
        self.variants = variants
        self.id = id
        self.name = name
        self.engine = engine
        self.components = components
        self.defaults = defaults
        self.licenseNote = licenseNote
        self.minMemoryGB = minMemoryGB
    }

    enum CodingKeys: String, CodingKey {
        case id, name, engine, components, defaults, variants
        case licenseNote = "license_note"
        case minMemoryGB = "min_memory_gb"
    }

    /// Total download size, or nil when any component has no declared size.
    public var totalSizeBytes: Int64? {
        var total: Int64 = 0
        for component in components {
            guard let size = component.sizeBytes else { return nil }
            total += size
        }
        return total
    }
}

extension ModelRecipe {
    public enum ComponentRole: String, Codable, Sendable, CaseIterable {
        /// A single-file checkpoint that carries everything (SD 1.x, SDXL).
        case checkpoint
        case diffusionModel = "diffusion_model"
        /// A language model used as the text encoder (Qwen-Image and similar).
        case llm
        case vae
        /// CLIP and T5 text encoders, used by the Flux and SD3 families.
        case clipL = "clip_l"
        case clipG = "clip_g"
        case t5xxl
    }

    public struct Component: Codable, Sendable, Equatable {
        public var role: ComponentRole
        /// Hugging Face repo id, e.g. `Comfy-Org/Qwen-Image-2.1`.
        public var repo: String
        /// Path of the file inside the repo.
        public var file: String
        /// Commit to download from. Falls back to `main` when absent.
        public var revision: String?
        public var sizeBytes: Int64?
        public var sha256: String?

        public init(
            role: ComponentRole,
            repo: String,
            file: String,
            revision: String? = nil,
            sizeBytes: Int64? = nil,
            sha256: String? = nil
        ) {
            self.role = role
            self.repo = repo
            self.file = file
            self.revision = revision
            self.sizeBytes = sizeBytes
            self.sha256 = sha256
        }

        enum CodingKeys: String, CodingKey {
            case role, repo, file, revision, sha256
            case sizeBytes = "size_bytes"
        }
    }

    public struct GenerationDefaults: Codable, Sendable, Equatable {
        public var steps: Int
        public var cfg: Double
        public var sampler: String
        public var width: Int
        public var height: Int
        /// Explicit noise schedule. Needs `steps + 1` values when present.
        public var sigmas: [Double]?
        public var flashAttention: Bool?
        /// Noise scheduler by its stable-diffusion.cpp name. The engine's default when absent.
        public var scheduler: String?
        /// Distilled guidance, used by guidance-distilled models such as Flux.
        public var guidance: Double?
        /// Flow shift for flow-matching models. The model's own default when absent.
        public var flowShift: Double?

        public init(
            steps: Int,
            cfg: Double,
            sampler: String,
            width: Int,
            height: Int,
            sigmas: [Double]? = nil,
            flashAttention: Bool? = nil,
            scheduler: String? = nil,
            guidance: Double? = nil,
            flowShift: Double? = nil
        ) {
            self.scheduler = scheduler
            self.guidance = guidance
            self.flowShift = flowShift
            self.steps = steps
            self.cfg = cfg
            self.sampler = sampler
            self.width = width
            self.height = height
            self.sigmas = sigmas
            self.flashAttention = flashAttention
        }

        enum CodingKeys: String, CodingKey {
            case steps, cfg, sampler, width, height, sigmas, scheduler, guidance
            case flashAttention = "flash_attention"
            case flowShift = "flow_shift"
        }
    }
}
