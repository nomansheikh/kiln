import Foundation

extension ModelLibrary {
    /// Imports the recipe file the user chose in a file importer, holding its
    /// security scope for as long as the file is being read.
    func importPickedRecipe(_ result: Result<URL, any Error>) throws {
        let file = try result.get()
        let scoped = file.startAccessingSecurityScopedResource()
        defer {
            if scoped { file.stopAccessingSecurityScopedResource() }
        }
        try importRecipe(from: file)
    }
}
