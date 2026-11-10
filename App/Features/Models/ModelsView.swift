import SwiftUI
import UniformTypeIdentifiers

/// The Models screen: curated recipes followed by popular Hugging Face models,
/// or Hugging Face search results while the user is searching.
struct ModelsView: View {
    @Environment(AppModel.self) private var model

    @State private var searchText = ""
    @State private var showsDownloadedOnly = false
    @State private var isImporting = false
    @State private var importError: String?

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Models", subtitle: "Curated recipes and Hugging Face checkpoints") {
                headerControls
            }
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !query.isEmpty {
                        HubSearchResults(query: query, title: "Hugging Face results")
                    } else {
                        ModelsRecipeList(showsDownloadedOnly: showsDownloadedOnly)
                        if !showsDownloadedOnly {
                            // No padding here: this view expands to many cards, and a
                            // modifier on it would be applied to each one.
                            HubSearchResults(query: "", title: "Popular on Hugging Face", isFollowingSection: true)
                        }
                    }
                }
                .frame(maxWidth: Theme.contentWidth)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importRecipe(result)
        }
        .alert("Could Not Import Recipe", isPresented: Binding(isPresenting: $importError)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Header

    private var headerControls: some View {
        HStack(spacing: 8) {
            ModelsSearchField(text: $searchText)
            DownloadedFilterChip(isOn: $showsDownloadedOnly)
            Button {
                isImporting = true
            } label: {
                Label("Import Recipe", systemImage: "square.and.arrow.down")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(SoftButtonStyle())
            .help("Add a model recipe from a JSON file")
        }
    }

    // MARK: - Importing

    private func importRecipe(_ result: Result<URL, any Error>) {
        do {
            try model.library.importPickedRecipe(result)
        } catch {
            importError = error.localizedDescription
        }
    }
}
