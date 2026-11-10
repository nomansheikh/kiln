import SwiftUI
import UniformTypeIdentifiers

/// The Models screen: curated recipes, or Hugging Face results while the user is searching.
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

            Group {
                if query.isEmpty {
                    ModelsRecipeList(showsDownloadedOnly: showsDownloadedOnly)
                } else {
                    HubSearchResults(query: query)
                }
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
