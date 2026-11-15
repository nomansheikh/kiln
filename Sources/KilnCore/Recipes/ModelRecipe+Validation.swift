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
    case missingDefaults
    case invalidSpeech(String)
    case invalidLanguages
    case invalidVariant(String)

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
        case .invalidSpeech(let reason):
            "The speech settings are invalid: \(reason)."
        case .invalidLanguages:
            "\"languages\" needs at least one language code, such as \"en\", each listed once."
        case .missingDefaults:
            "An image model needs default settings: steps, CFG, sampler, width and height."
        case .invalidVariant(let id):
            "The variant \"\(id)\" needs a unique id of lowercase letters, digits, dots, dashes and underscores, and a name."
        }
    }
}

extension ModelRecipe {
    public func validate() throws(RecipeValidationError) {
        guard Self.isValidSlug(id) else { throw .invalidID(id) }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw .emptyName }
        if let defaults {
            try defaults.validate()
        } else if outputKind == .image {
            throw .missingDefaults
        }
        if let languages {
            // A code is handed to the engine as it is, so it must look like one.
            let isCode: (String) -> Bool = { code in
                (2...12).contains(code.count) && code.allSatisfy { $0.isASCII && ($0.isLetter || $0 == "-" || $0 == "_") }
            }
            guard !languages.isEmpty, Set(languages).count == languages.count, languages.allSatisfy(isCode) else {
                throw .invalidLanguages
            }
        }
        if outputKind == .audio {
            guard let speech, Self.isSafeName(speech.family) else {
                throw .invalidSpeech("a model that makes audio needs \"speech\" with a \"family\" of letters, digits, dashes and underscores")
            }
            if let voices = speech.voices, voices.isEmpty || Set(voices).count != voices.count {
                throw .invalidSpeech("\"voices\" needs at least one name, each listed once")
            }
            // The engine looks a voice up by name, in some models as a file, so a
            // name must not be able to point anywhere else.
            if let unsafe = self.voices.first(where: { !Self.isSafeName($0) }) {
                throw .invalidSpeech("the voice name \"\(unsafe)\" may use only letters, digits, dots, dashes and underscores")
            }
            // A tag is typed into the text, so it must be short and on one line.
            let isTag: (String) -> Bool = { tag in
                (1...40).contains(tag.count) && tag == tag.trimmingCharacters(in: .whitespacesAndNewlines)
                    && !tag.unicodeScalars.contains(where: CharacterSet.controlCharacters.union(.newlines).contains)
            }
            if let styles = speech.styles {
                // The words are joined with commas for the engine, so none may hold one.
                let words = styles.flatMap(\.options)
                let isWord: (String) -> Bool = { isTag($0) && !$0.contains(",") }
                guard !styles.isEmpty, speech.instruction == nil, Set(styles.map(\.name)).count == styles.count,
                      styles.allSatisfy({ isTag($0.name) && !$0.options.isEmpty }),
                      Set(words).count == words.count, words.allSatisfy(isWord)
                else {
                    throw .invalidSpeech("\"styles\" needs named groups of words, each word listed once and without commas, and cannot be combined with \"instruction\"")
                }
            }
            if speech.referenceText != nil, speech.reference == nil {
                throw .invalidSpeech("\"reference_text\" needs \"reference\": the words belong to a recording of a voice")
            }
            if let speakers = speech.speakers,
               speakers.max < 2 || !speakers.line.contains("{n}") || !speakers.line.contains("{text}") {
                throw .invalidSpeech("\"speakers\" needs a \"max\" of at least 2 and a \"line\" with {n} and {text}")
            }
            if let tags = speech.tags, tags.isEmpty || Set(tags).count != tags.count || !tags.allSatisfy(isTag) {
                throw .invalidSpeech("\"tags\" needs at least one tag of at most 40 characters, each listed once")
            }
        }
        if let baseModel, !Component.isValidRepo(baseModel) { throw .invalidRepo(baseModel) }

        guard let variants, !variants.isEmpty else {
            try Self.validate(components)
            return
        }
        // With variants the shared list may be empty, but every variant must
        // add up to a complete, valid set of files.
        try Self.validate(components, allowEmpty: true)
        var seenIDs: Set<String> = []
        for variant in variants {
            guard Self.isValidSlug(variant.id), seenIDs.insert(variant.id).inserted,
                  !variant.name.trimmingCharacters(in: .whitespaces).isEmpty
            else {
                throw .invalidVariant(variant.id)
            }
            try Self.validate(variant.components)
            try Self.validate(resolved(variant.id).components)
        }
    }

    /// A name that is safe to hand to an engine: no path separators and nothing
    /// that could be read as a parent folder.
    static func isSafeName(_ text: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return !text.isEmpty && !text.hasPrefix(".") && text.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func isValidSlug(_ text: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
        return !text.isEmpty && !text.hasPrefix(".") && text.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func validate(_ components: [Component], allowEmpty: Bool = false) throws(RecipeValidationError) {
        guard allowEmpty || !components.isEmpty else { throw .noComponents }
        var seenRoles: Set<ComponentRole> = []
        var seenVoices: Set<String> = []
        for component in components {
            if component.role.mayRepeat {
                // Voices are told apart by name and other files by path, so no two may share one.
                let key = component.role == .voice ? "voice:" + component.voiceName : "file:" + component.file
                guard seenVoices.insert(key).inserted else { throw .duplicateRole(component.role) }
            } else {
                guard seenRoles.insert(component.role).inserted else { throw .duplicateRole(component.role) }
            }
            try component.validate()
        }
    }
}

extension ModelRecipe.Component {
    static func isValidRepo(_ repo: String) -> Bool {
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    func validate() throws(RecipeValidationError) {
        guard Self.isValidRepo(repo) else { throw .invalidRepo(repo) }
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

extension ModelRecipe.ImageDefaults {
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
