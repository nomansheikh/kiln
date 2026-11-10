import SwiftUI

/// The empty state: a headline with the composer centred under it.
struct GenerateGreeting: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let hasModels = !model.library.installedRecipes.isEmpty

        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Text("What do you want to create?")
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 26)

            PromptComposer()
                .disabled(!hasModels)

            Group {
                if hasModels {
                    PromptSuggestionChips { model.generation.draft.prompt = $0.prompt }
                } else {
                    noModelsHint
                }
            }
            .padding(.top, 18)

            // More space below than above lifts the group to the optical centre.
            Spacer(minLength: 24)
            Spacer(minLength: 0).frame(maxHeight: 72)
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 24)
    }

    private var noModelsHint: some View {
        HStack(spacing: 4) {
            Text("No models installed yet.")
                .foregroundStyle(.secondary)
            Button("Download a model") { model.selection = .models }
                .buttonStyle(.link)
        }
        .font(.callout)
    }
}
