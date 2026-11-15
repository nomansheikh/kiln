import SwiftUI

/// What sits under the Speech composer while there are no clips: starter
/// texts, or a pointer to Models when no voice model is installed yet.
struct SpeechStarters: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.speech.recipes.isEmpty {
            HStack(spacing: 4) {
                Text("No voice model installed yet.")
                    .foregroundStyle(.secondary)
                Button("Download a voice model") { model.browseModels(for: .textToSpeech) }
                    .buttonStyle(.link)
            }
            .font(.callout)
        } else {
            PromptSuggestionChips(suggestions: PromptSuggestion.speech) { model.speech.text = $0.prompt }
        }
    }
}
