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

    public init(
        id: String,
        name: String,
        engine: String,
        components: [Component],
        defaults: GenerationDefaults,
        licenseNote: String? = nil,
        minMemoryGB: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.engine = engine
        self.components = components
        self.defaults = defaults
        self.licenseNote = licenseNote
        self.minMemoryGB = minMemoryGB
    }

    enum CodingKeys: String, CodingKey {
        case id, name, engine, components, defaults
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
        case llm
        case vae
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

        public init(
            steps: Int,
            cfg: Double,
            sampler: String,
            width: Int,
            height: Int,
            sigmas: [Double]? = nil,
            flashAttention: Bool? = nil
        ) {
            self.steps = steps
            self.cfg = cfg
            self.sampler = sampler
            self.width = width
            self.height = height
            self.sigmas = sigmas
            self.flashAttention = flashAttention
        }

        enum CodingKeys: String, CodingKey {
            case steps, cfg, sampler, width, height, sigmas
            case flashAttention = "flash_attention"
        }
    }
}

// MARK: - Validation

public enum RecipeValidationError: Error, Equatable, LocalizedError {
    case invalidID(String)
    case emptyName
    case noComponents
    case duplicateRole(ModelRecipe.ComponentRole)
    case invalidRepo(String)
    case unsafeFilePath(String)
    case invalidSHA256(file: String)
    case invalidSize(file: String)
    case invalidDefaults(String)

    public var errorDescription: String? {
        switch self {
        case .invalidID(let id):
            "Recipe id \"\(id)\" must use only lowercase letters, digits, dots, dashes and underscores."
        case .emptyName:
            "The recipe has no name."
        case .noComponents:
            "The recipe lists no files to download."
        case .duplicateRole(let role):
            "The recipe lists more than one \"\(role.rawValue)\" component."
        case .invalidRepo(let repo):
            "\"\(repo)\" is not a Hugging Face repo id (expected owner/name)."
        case .unsafeFilePath(let file):
            "The file path \"\(file)\" is not allowed."
        case .invalidSHA256(let file):
            "The SHA-256 for \(file) is not 64 hexadecimal characters."
        case .invalidSize(let file):
            "The size for \(file) must be greater than zero."
        case .invalidDefaults(let reason):
            "The default settings are invalid: \(reason)."
        }
    }
}

extension ModelRecipe {
    public func validate() throws(RecipeValidationError) {
        let idCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
        guard !id.isEmpty, id.unicodeScalars.allSatisfy(idCharacters.contains), !id.hasPrefix(".") else {
            throw .invalidID(id)
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw .emptyName }
        guard !components.isEmpty else { throw .noComponents }

        var seenRoles: Set<ComponentRole> = []
        for component in components {
            guard seenRoles.insert(component.role).inserted else { throw .duplicateRole(component.role) }
            try component.validate()
        }
        try defaults.validate()
    }
}

extension ModelRecipe.Component {
    func validate() throws(RecipeValidationError) {
        let repoParts = repo.split(separator: "/", omittingEmptySubsequences: false)
        guard repoParts.count == 2, repoParts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw .invalidRepo(repo)
        }
        // Recipes can be imported from anywhere, so the path must stay inside the model folder.
        let pathParts = file.split(separator: "/", omittingEmptySubsequences: false)
        guard !file.isEmpty, !file.contains("\\"),
              pathParts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw .unsafeFilePath(file)
        }
        if let sha256 {
            guard sha256.count == 64, sha256.allSatisfy(\.isHexDigit) else { throw .invalidSHA256(file: file) }
        }
        if let sizeBytes, sizeBytes <= 0 { throw .invalidSize(file: file) }
    }
}

extension ModelRecipe.GenerationDefaults {
    func validate() throws(RecipeValidationError) {
        guard steps > 0 else { throw .invalidDefaults("steps must be greater than zero") }
        guard cfg >= 0 else { throw .invalidDefaults("cfg cannot be negative") }
        guard !sampler.isEmpty else { throw .invalidDefaults("sampler is missing") }
        guard width > 0, height > 0 else { throw .invalidDefaults("width and height must be greater than zero") }
        if let sigmas, sigmas.count != steps + 1 {
            throw .invalidDefaults("\(steps) steps need \(steps + 1) sigmas, found \(sigmas.count)")
        }
    }
}
