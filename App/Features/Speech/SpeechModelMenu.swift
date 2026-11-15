import KilnCore
import SwiftUI

/// The capsule in the top-left corner of the Speech screen that names the
/// voice model and switches it, like the one on the Generate screen.
struct SpeechModelMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let speech = model.speech

        if speech.recipes.isEmpty {
            Button { model.browseModels(for: .textToSpeech) } label: {
                label("No voice model")
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Download a voice model")
        } else {
            Menu {
                ForEach(speech.recipes) { recipe in
                    Toggle(isOn: Binding(
                        get: { recipe.id == speech.recipeID },
                        set: { _ in speech.selectRecipe(recipe) }
                    )) {
                        Text(verbatim: recipe.name)
                    }
                }
                Divider()
                Button("Get More Voice Models…") { model.browseModels(for: .textToSpeech) }
            } label: {
                label(speech.selectedRecipe?.name ?? "No voice model")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .pointerCursor()
            .menuIndicator(.hidden)
            .focusable(false)
            .fixedSize()
            .disabled(speech.isUsingEngine)
            .help("Voice model")
        }
    }

    private func label(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cube")
                .foregroundStyle(.secondary)
            Text(verbatim: name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 260)
                .fixedSize()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .contentShape(Capsule())
    }
}
