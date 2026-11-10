import KilnCore
import SwiftUI

/// One Hugging Face repo in the search results, with its files behind a disclosure row.
struct HubResultCard: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            stats

            ModelsDisclosureRow(title: "Files", isExpanded: $isExpanded)
            if isExpanded {
                HubFileList(info: info, isLoading: isLoading, failure: failure, retry: loadFiles, download: download)
            }
        }
        .modelsCard(hovering: hovering)
        .onHover { hovering = $0 }
        .onChange(of: isExpanded) { _, expanded in
            if expanded { loadFiles() }
        }
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
            if let pageURL {
                Link(destination: pageURL) {
                    HStack(spacing: 4) {
                        Text("Open on Hugging Face")
                        Image(systemName: "arrow.up.right")
                            .imageScale(.small)
                    }
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
                }
                .foregroundStyle(.secondary)
                .help(pageURL.absoluteString)
            }
        }
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
        }
        .lineLimit(1)
    }
}
