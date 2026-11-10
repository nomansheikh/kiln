import Foundation

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
