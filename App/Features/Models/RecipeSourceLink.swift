import KilnCore
import SwiftUI

/// Opens a recipe's source on Hugging Face: a direct link when all its files
/// come from one repo, otherwise a menu listing each repo.
struct RecipeSourceLink: View {
    @Environment(\.openURL) private var openURL
    let recipe: ModelRecipe

    var body: some View {
        let repos = recipe.sourceRepos
        if repos.count == 1, let url = Self.pageURL(for: repos[0]) {
            Link(destination: url) { label }
                .foregroundStyle(.secondary)
                .help(url.absoluteString)
        } else if repos.count > 1 {
            Menu {
                ForEach(repos, id: \.self) { repo in
                    Button(repo) {
                        if let url = Self.pageURL(for: repo) { openURL(url) }
                    }
                }
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("This model's files come from \(repos.count) Hugging Face repos")
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Text("Hugging Face")
            Image(systemName: "arrow.up.right")
                .imageScale(.small)
        }
        .font(.caption.weight(.medium))
        .fixedSize()
    }

    private static func pageURL(for repo: String) -> URL? {
        URL(string: "https://huggingface.co/\(repo)")
    }
}
