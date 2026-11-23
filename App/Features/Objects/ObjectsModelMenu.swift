import KilnCore
import SwiftUI

/// The capsule in the top-left corner of the 3D screen that names the model
/// and switches it, like the ones on the Generate and Speech screens.
struct ObjectsModelMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let studio = model.studio

        if studio.recipes.isEmpty {
            Button { model.browseModels(for: .objects) } label: {
                label("No 3D model")
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Download a model that makes 3D objects")
        } else {
            Menu {
                ForEach(studio.recipes) { recipe in
                    Toggle(isOn: Binding(
                        get: { recipe.id == studio.draft.recipeID },
                        set: { _ in studio.selectRecipe(recipe) }
                    )) {
                        Text(verbatim: recipe.name)
                        if let variant = recipe.selectedVariantID {
                            Text(verbatim: variant.uppercased())
                        }
                    }
                }
                Divider()
                Button("Get More 3D Models…") { model.browseModels(for: .objects) }
            } label: {
                label(studio.selectedRecipe?.name ?? "No 3D model")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .pointerCursor()
            .menuIndicator(.hidden)
            .focusable(false)
            .fixedSize()
            .disabled(studio.isGenerating)
            .help("3D model")
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
