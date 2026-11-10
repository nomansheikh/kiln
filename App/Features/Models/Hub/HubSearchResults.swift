import KilnCore
import SwiftUI

/// Hugging Face search results shown on the Models screen while the user types.
struct HubSearchResults: View {
    @Environment(AppModel.self) private var model

    private let query: String

    @State private var search = HubSearchModel()
    @State private var attempt = 0
    @State private var downloadError: String?

    init(query: String) {
        self.query = query
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .results(let summaries):
            results(summaries)
        }
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Searching Hugging Face…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Search failed", systemImage: "exclamationmark.triangle")
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
    }

    private func results(_ summaries: [HFModelSummary]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ModelsSectionTitle(text: "Hugging Face results", count: summaries.count)
                ForEach(summaries) { summary in
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
            .frame(maxWidth: Theme.contentWidth)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
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
