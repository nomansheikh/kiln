import SwiftUI

/// What sits under the composer on an empty chat: starter prompts, or a
/// pointer to Models when nothing is installed yet.
struct GenerateStarters: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.library.installedRecipes.isEmpty {
            HStack(spacing: 4) {
                Text("No models installed yet.")
                    .foregroundStyle(.secondary)
                Button("Download a model") { model.selection = .models }
                    .buttonStyle(.link)
            }
            .font(.callout)
        } else {
            PromptSuggestionChips { model.generation.draft.prompt = $0.prompt }
        }
    }
}
