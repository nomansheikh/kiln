import KilnCore
import SwiftUI

/// A section of Hugging Face models on the Models screen: the most downloaded
/// text-to-image models for an empty query, otherwise the matches for it.
/// It is laid out inside the Models screen's scroll view.
struct HubSearchResults: View {
    @Environment(AppModel.self) private var model

    private let query: String
    private let title: String
    /// Adds space above the section title when another section comes before it.
    private let isFollowingSection: Bool

    @AppStorage("models.hubExpanded") private var browseExpanded = true
    @State private var search = HubSearchModel()
    @State private var attempt = 0
    @State private var downloadError: String?

    init(query: String, title: String, isFollowingSection: Bool = false) {
        self.query = query
        self.title = title
        self.isFollowingSection = isFollowingSection
    }

    var body: some View {
        content
            .task(id: HubSearchKey(query: query, attempt: attempt)) {
                await search.search(query, using: model.library.hub)
            }
            .alert(
                "Download could not start",
                isPresented: Binding(isPresenting: $downloadError),
                presenting: downloadError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        switch search.phase {
        case .loading:
            loading
        case .failed(let message):
            failed(message)
        case .results(let summaries) where summaries.isEmpty:
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .results(let summaries):
            results(summaries)
        }
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(query.isEmpty ? "Loading popular models…" : "Searching Hugging Face…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Hugging Face could not be reached", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button {
                attempt += 1
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SoftButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func results(_ summaries: [HFModelSummary]) -> some View {
        Group {
            // The browse list can be collapsed; search results are what was asked for, so they stay open.
            ModelsSectionTitle(text: title, count: summaries.count, isExpanded: isFollowingSection ? $browseExpanded : nil)
                .padding(.top, isFollowingSection ? 14 : 0)
            ForEach(isFollowingSection && !browseExpanded ? [] : summaries) { summary in
                HubResultCard(
                    summary: summary,
                    info: search.infos[summary.id],
                    isLoading: search.loadingRepos.contains(summary.id),
                    failure: search.failures[summary.id],
                    loadFiles: { search.loadInfo(for: summary.id, using: model.library.hub) },
                    download: download
                )
            }
        }
    }

    // MARK: - Actions

    private func download(_ file: HFFile, in info: HFModelInfo) {
        do {
            try model.library.downloadFromHub(file, in: info)
        } catch {
            downloadError = HubSearchModel.message(for: error)
        }
    }
}
