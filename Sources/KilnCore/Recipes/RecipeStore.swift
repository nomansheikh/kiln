import Foundation

/// Loads recipes shipped with the app and recipes the user imported.
public struct RecipeStore: Sendable {
    public struct LoadFailure: Sendable {
        public let file: URL
        public let message: String
    }

    public struct LoadResult: Sendable {
        public var recipes: [ModelRecipe] = []
        public var failures: [LoadFailure] = []
        /// Ids of the recipes that came from the user's folder rather than the app.
        public var userRecipeIDs: Set<String> = []
    }

    public enum ImportError: Error, Equatable, LocalizedError {
        case idTaken(String)

        public var errorDescription: String? {
            switch self {
            case .idTaken(let id): "A built-in recipe already uses the id \"\(id)\"."
            }
        }
    }

    public let bundledDirectory: URL
    public let userDirectory: URL

    public init(bundledDirectory: URL, userDirectory: URL) {
        self.bundledDirectory = bundledDirectory
        self.userDirectory = userDirectory
    }

    public static func decode(_ data: Data) throws -> ModelRecipe {
        let recipe = try JSONDecoder().decode(ModelRecipe.self, from: data)
        try recipe.validate()
        return recipe
    }

    /// Bundled recipes win when a user recipe reuses one of their ids.
    public func loadAll() -> LoadResult {
        var result = LoadResult()
        var seenIDs: Set<String> = []
        for directory in [bundledDirectory, userDirectory] {
            for file in Self.recipeFiles(in: directory) {
                do {
                    let recipe = try Self.decode(Data(contentsOf: file))
                    guard seenIDs.insert(recipe.id).inserted else {
                        result.failures.append(LoadFailure(file: file, message: "Duplicate recipe id \"\(recipe.id)\"."))
                        continue
                    }
                    result.recipes.append(recipe)
                    if directory == userDirectory {
                        result.userRecipeIDs.insert(recipe.id)
                    }
                } catch {
                    result.failures.append(LoadFailure(file: file, message: Self.describe(error)))
                }
            }
        }
        return result
    }

    /// Validates a recipe file and copies it into the user directory.
    @discardableResult
    public func importRecipe(from file: URL) throws -> ModelRecipe {
        let data = try Data(contentsOf: file)
        let recipe = try Self.decode(data)

        let bundledIDs = Self.recipeFiles(in: bundledDirectory)
            .compactMap { try? Self.decode(Data(contentsOf: $0)).id }
        guard !bundledIDs.contains(recipe.id) else { throw ImportError.idTaken(recipe.id) }

        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        try data.write(to: userDirectory.appendingPathComponent("\(recipe.id).json"), options: .atomic)
        return recipe
    }

    private static func recipeFiles(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _):
            "Missing field \"\(key.stringValue)\"."
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "Wrong value for \"\(context.codingPath.map(\.stringValue).joined(separator: "."))\"."
        case DecodingError.dataCorrupted(let context):
            context.codingPath.isEmpty
                ? "The file is not valid JSON."
                : "Unsupported value for \"\(context.codingPath.map(\.stringValue).joined(separator: "."))\"."
        default:
            error.localizedDescription
        }
    }
}
