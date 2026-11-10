import KilnCore
import SwiftUI

/// Points from a Hugging Face repo to the recipe that already covers it, so the
/// user gets every part of the model instead of picking files by hand.
struct HubRecipeSuggestion: View {
    @Environment(AppModel.self) private var model
    let recipe: ModelRecipe

    var body: some View {
        let library = model.library
        let status = library.downloadStatus(for: recipe)

        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kiln has a recipe for this: \(recipe.name)")
                    .font(.callout.weight(.medium))
                Text("One click downloads every part it needs, with the right settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if library.isInstalled(recipe) {
                Button("Use") { model.use(recipe) }
                    .buttonStyle(AccentButtonStyle())
            } else if let status, status.isActive {
                Text(status.percentText ?? "Starting…")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Button("Download") { library.download(recipe) }
                    .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(10)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
