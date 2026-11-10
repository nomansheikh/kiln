import KilnCore
import SwiftUI

/// The capsule in the top-left corner that names the current model and switches it.
struct GenerateModelPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let installed = model.library.installedRecipes
        if installed.isEmpty {
            Button { model.selection = .models } label: {
                label("No model")
            }
            .buttonStyle(.plain)
            .help("Download a model")
        } else {
            // A Menu of Buttons rather than a Picker so every change goes through selectRecipe(_:).
            Menu {
                ForEach(installed) { recipe in
                    Button { model.generation.selectRecipe(recipe) } label: {
                        if recipe.id == model.generation.draft.recipeID {
                            Label(recipe.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: recipe.name)
                        }
                    }
                }
            } label: {
                label(model.generation.selectedRecipe?.name ?? "No model")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Model")
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
