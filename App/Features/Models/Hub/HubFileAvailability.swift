import KilnCore

/// What the user can do with one file of a Hugging Face repo.
enum HubFileAvailability {
    /// Not on this Mac; it can be downloaded.
    case available
    /// Queued, downloading or being verified.
    case transferring(DownloadStatus)
    case installed
}

extension ModelLibrary {
    /// Whether a file from a Hugging Face repo is already installed or on its way,
    /// judged by the recipe that was made for it when its download started.
    func availability(of file: HFFile, in info: HFModelInfo) -> HubFileAvailability {
        let recipe = recipes.first { recipe in
            recipe.components.contains { $0.repo == info.id && $0.file == file.path }
        }
        guard let recipe else { return .available }
        if isInstalled(recipe) {
            return .installed
        }
        if let status = downloadStatus(for: recipe), status.isActive {
            return .transferring(status)
        }
        return .available
    }
}
