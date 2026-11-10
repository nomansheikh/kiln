import Foundation

public enum RecipeCatalogError: Error, Equatable, LocalizedError {
    case http(status: Int)
    case unreadableIndex

    public var errorDescription: String? {
        switch self {
        case .http(let status): "The recipe list could not be fetched (HTTP \(status))."
        case .unreadableIndex: "The recipe list could not be read."
        }
    }
}

/// Fetches the curated recipes published in the project's repository, so new
/// recipes reach users without an app release.
///
/// Recipes are data: file locations, checksums and settings. Each one is
/// validated before it is kept, and every file it names is still verified
/// against its SHA-256 when downloaded.
public struct RecipeCatalog: Sendable {
    public static let defaultIndexURL = URL(string: "https://raw.githubusercontent.com/nomansheikh/kiln/main/recipes/index.json")!

    private struct Index: Decodable {
        let version: Int
        let recipes: [String]
    }

    private static let supportedVersion = 1
    private static let maximumRecipes = 500
    private static let maximumRecipeBytes = 512 * 1024

    private let indexURL: URL
    private let cacheDirectory: URL
    private let transport: any HTTPTransport

    public init(indexURL: URL = RecipeCatalog.defaultIndexURL, cacheDirectory: URL, transport: any HTTPTransport = URLSession.shared) {
        self.indexURL = indexURL
        self.cacheDirectory = cacheDirectory
        self.transport = transport
    }

    /// Replaces the cached recipes with the published set and returns how many were kept.
    /// A recipe this version cannot read is skipped; a failed index leaves the cache untouched.
    @discardableResult
    public func refresh() async throws -> Int {
        let indexData = try await fetch(indexURL)
        guard let index = try? JSONDecoder().decode(Index.self, from: indexData),
              index.version == Self.supportedVersion, index.recipes.count <= Self.maximumRecipes
        else {
            throw RecipeCatalogError.unreadableIndex
        }

        var recipes: [(name: String, data: Data)] = []
        for name in index.recipes where Self.isSafeFileName(name) {
            guard let data = try? await fetch(indexURL.deletingLastPathComponent().appendingPathComponent(name)),
                  data.count <= Self.maximumRecipeBytes,
                  let recipe = try? RecipeStore.decode(data), "\(recipe.id).json" == name
            else { continue }
            recipes.append((name, data))
        }

        // Build the new set beside the old one and swap, so a crash never leaves half a cache.
        let files = FileManager.default
        let staging = cacheDirectory.deletingLastPathComponent()
            .appendingPathComponent(".\(cacheDirectory.lastPathComponent)-\(UUID().uuidString)")
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        for recipe in recipes {
            try recipe.data.write(to: staging.appendingPathComponent(recipe.name))
        }
        if files.fileExists(atPath: cacheDirectory.path) {
            try files.removeItem(at: cacheDirectory)
        }
        try files.moveItem(at: staging, to: cacheDirectory)
        return recipes.count
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RecipeCatalogError.unreadableIndex }
        guard http.statusCode == 200 else { throw RecipeCatalogError.http(status: http.statusCode) }
        return data
    }

    /// The index is remote input: a name must be a plain recipe file, never a path.
    private static func isSafeFileName(_ name: String) -> Bool {
        name.hasSuffix(".json") && !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".")
            && !RecipeStore.reservedFileNames.contains(name)
    }
}
