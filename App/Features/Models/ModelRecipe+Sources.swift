import KilnCore

extension ModelRecipe {
    /// The Hugging Face repos the recipe's files come from, in order, without repeats.
    var sourceRepos: [String] {
        var seen: Set<String> = []
        return components.map(\.repo).filter { seen.insert($0).inserted }
    }

    /// The accounts that own `sourceRepos`, in order, without repeats.
    var sourceOwners: [String] {
        var seen: Set<String> = []
        return sourceRepos
            .map { $0.split(separator: "/").first.map(String.init) ?? $0 }
            .filter { seen.insert($0).inserted }
    }

    /// "1 file" or "3 files".
    var fileCountText: String {
        components.count == 1 ? "1 file" : "\(components.count) files"
    }
}
