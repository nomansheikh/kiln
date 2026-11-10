import KilnCore
import SwiftUI

/// One Hugging Face repo in the search results, with its files behind a disclosure row.
struct HubResultCard: View {
    @Environment(AppModel.self) private var model
    let summary: HFModelSummary
    let info: HFModelInfo?
    let isLoading: Bool
    let failure: HubRepoFailure?
    let loadFiles: () -> Void
    let download: (HFFile, HFModelInfo) -> Void

    @State private var isExpanded = false
    @State private var hovering = false

    private var repoName: String {
        summary.id.split(separator: "/").last.map(String.init) ?? summary.id
    }

    private var pageURL: URL? {
        URL(string: "https://huggingface.co/\(summary.id)")
    }

    /// The one answer shown for this repo: what the user can do with it.
    private var support: HubRepoSupport {
        model.library.support(forRepo: summary.id, info: info, failed: failure != nil)
    }

    private var isUnsupported: Bool {
        if case .unsupported = support { true } else { false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            stats
            if case .recipe(let recipe) = support {
                HubRecipeSuggestion(recipe: recipe)
            }
            if isUnsupported {
                unsupportedNote
            }

            ModelsDisclosureRow(title: "All files", isExpanded: $isExpanded)
            if isExpanded {
                HubFileList(info: info, isLoading: isLoading, failure: failure, retry: loadFiles, download: download)
            }
        }
        .modelsCard(hovering: hovering)
        .onHover { hovering = $0 }
        // The file list decides what the card offers, so it is fetched as the card appears.
        .task { loadFiles() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ModelsMonogram(name: summary.author.isEmpty ? repoName : summary.author)
            VStack(alignment: .leading, spacing: 3) {
                Text(repoName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(summary.id)
                Text(summary.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HubRepoAction(support: support, download: download)
        }
        .opacity(isUnsupported ? 0.7 : 1)
    }

    /// Says plainly why there is nothing to download, and where to ask for support.
    private var unsupportedNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("This model comes in several files and Kiln has no recipe for it yet.")
                .foregroundStyle(.secondary)
            if let requestURL = URL(string: "https://github.com/nomansheikh/kiln/issues/new?template=recipe_request.yml") {
                Link("Request it", destination: requestURL)
            }
        }
        .font(.callout)
    }

    private var stats: some View {
        HStack(spacing: 6) {
            Pill(text: summary.downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
                .help("Downloads")
            Pill(text: summary.likes.formatted(.number.notation(.compactName)), systemImage: "heart")
                .help("Likes")
            if let license = summary.license {
                Pill(text: license, systemImage: "doc.text")
                    .help("License")
            }
            Spacer(minLength: 0)
            if let pageURL {
                Link(destination: pageURL) {
                    HStack(spacing: 4) {
                        Text("Hugging Face")
                        Image(systemName: "arrow.up.right")
                            .imageScale(.small)
                    }
                    .font(.caption.weight(.medium))
                    .fixedSize()
                }
                .foregroundStyle(.secondary)
                .help(pageURL.absoluteString)
            }
        }
        .lineLimit(1)
    }
}
