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

    /// Files that live beside the recipes but are not recipes themselves.
    public static let reservedFileNames: Set<String> = ["index.json", "schema.json"]

    public let bundledDirectory: URL
    public let userDirectory: URL
    /// Curated recipes fetched after the app was built. One of these replaces
    /// the bundled recipe with the same id.
    public let remoteDirectory: URL?

    public init(bundledDirectory: URL, userDirectory: URL, remoteDirectory: URL? = nil) {
        self.bundledDirectory = bundledDirectory
        self.userDirectory = userDirectory
        self.remoteDirectory = remoteDirectory
    }

    public static func decode(_ data: Data) throws -> ModelRecipe {
        let recipe = try JSONDecoder().decode(ModelRecipe.self, from: data)
        try recipe.validate()
        return recipe
    }

    /// Curated recipes come first, a fetched copy replacing the bundled one with the
    /// same id. They win when a user recipe reuses one of their ids.
    public func loadAll() -> LoadResult {
        var result = LoadResult()
        var seenIDs: Set<String> = []

        // Fetched recipes are best-effort: one this version cannot read is simply not used.
        for file in remoteDirectory.map(Self.recipeFiles) ?? [] {
            if let recipe = try? Self.decode(Data(contentsOf: file)), seenIDs.insert(recipe.id).inserted {
                result.recipes.append(recipe)
            }
        }
        for file in Self.recipeFiles(in: bundledDirectory) {
            do {
                let recipe = try Self.decode(Data(contentsOf: file))
                if seenIDs.insert(recipe.id).inserted {
                    result.recipes.append(recipe)
                }
            } catch {
                result.failures.append(LoadFailure(file: file, message: Self.describe(error)))
            }
        }
        for file in Self.recipeFiles(in: userDirectory) {
            do {
                let recipe = try Self.decode(Data(contentsOf: file))
                guard seenIDs.insert(recipe.id).inserted else {
                    result.failures.append(LoadFailure(file: file, message: "Duplicate recipe id \"\(recipe.id)\"."))
                    continue
                }
                result.recipes.append(recipe)
                result.userRecipeIDs.insert(recipe.id)
            } catch {
                result.failures.append(LoadFailure(file: file, message: Self.describe(error)))
            }
        }
        result.recipes.sort { lhs, rhs in
            // Curated before user-added, each group by name.
            let lhsUser = result.userRecipeIDs.contains(lhs.id), rhsUser = result.userRecipeIDs.contains(rhs.id)
            guard lhsUser == rhsUser else { return !lhsUser }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
        return result
    }

    /// Validates a recipe file and copies it into the user directory.
    @discardableResult
    public func importRecipe(from file: URL) throws -> ModelRecipe {
        let data = try Data(contentsOf: file)
        let recipe = try Self.decode(data)

        let curatedIDs = (Self.recipeFiles(in: bundledDirectory) + (remoteDirectory.map(Self.recipeFiles) ?? []))
            .compactMap { try? Self.decode(Data(contentsOf: $0)).id }
        guard !curatedIDs.contains(recipe.id) else { throw ImportError.idTaken(recipe.id) }

        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        try data.write(to: userDirectory.appendingPathComponent("\(recipe.id).json"), options: .atomic)
        return recipe
    }

    private static func recipeFiles(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "json" && !reservedFileNames.contains($0.lastPathComponent) }
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
