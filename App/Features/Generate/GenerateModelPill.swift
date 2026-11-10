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
            // A Menu of Toggles rather than a Picker so every change goes through selectRecipe(_:),
            // while the menu still draws its own checkmark beside the current model.
            Menu {
                ForEach(installed) { recipe in
                    Toggle(isOn: Binding(
                        get: { recipe.id == model.generation.draft.recipeID },
                        set: { _ in model.generation.selectRecipe(recipe) }
                    )) {
                        Text(verbatim: recipe.name)
                    }
                }
                Divider()
                Button("Unload from Memory", systemImage: "memorychip") {
                    model.generation.unloadModel()
                }
                .disabled(model.generation.loadedRecipeID == nil || model.generation.phase.isBusy)
            } label: {
                label(model.generation.selectedRecipe?.name ?? "No model")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        .focusable(false)
            .focusable(false)
            .fixedSize()
            .help(model.generation.loadedRecipeID == nil ? "Model" : "Model (loaded in memory)")
        }
    }

    private func label(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cube")
                .foregroundStyle(.secondary)
                .overlay(alignment: .topTrailing) {
                    // A green dot while the model is held in memory.
                    if model.generation.loadedRecipeID != nil {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -2)
                    }
                }
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
