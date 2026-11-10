import Foundation

/// Where model files live on disk: `<root>/<owner>/<repo>/<file>`.
///
/// A file only appears at its final path after it was fully downloaded and
/// verified, so existence means "installed".
public struct ModelStorage: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Kiln/models`
    public static var defaultRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Kiln/models", isDirectory: true)
    }

    public func url(for component: ModelRecipe.Component) -> URL {
        root.appendingPathComponent(component.repo).appendingPathComponent(component.file)
    }

    public func isInstalled(_ component: ModelRecipe.Component) -> Bool {
        FileManager.default.fileExists(atPath: url(for: component).path)
    }

    public func isInstalled(_ recipe: ModelRecipe) -> Bool {
        recipe.components.allSatisfy(isInstalled)
    }

    public func missingComponents(of recipe: ModelRecipe) -> [ModelRecipe.Component] {
        recipe.components.filter { !isInstalled($0) }
    }

    /// Removes the recipe's files, leaving any file another recipe in `keeping` also uses.
    public func delete(_ recipe: ModelRecipe, keeping others: [ModelRecipe] = []) throws {
        let shared = Set(others.filter { $0.id != recipe.id }.flatMap(\.components).map { url(for: $0).path })
        for component in recipe.components {
            let file = url(for: component)
            guard !shared.contains(file.path) else { continue }
            for target in [file, FileDownloader.partialURL(for: file), FileDownloader.markerURL(for: file)]
            where FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            removeEmptyParents(of: file)
        }
    }

    private func removeEmptyParents(of file: URL) {
        var directory = file.deletingLastPathComponent().standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        while directory.path.hasPrefix(rootPath + "/"),
              (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: directory)
            directory = directory.deletingLastPathComponent()
        }
    }
}
