import KilnCore
import SwiftUI

/// The pill on a model card that shows which variant is selected and switches
/// between them. Each choice lists its size and whether it fits this Mac.
struct RecipeVariantMenu: View {
    @Environment(AppModel.self) private var model
    let recipe: ModelRecipe

    var body: some View {
        let library = model.library
        let options = library.variants(of: recipe)
        let current = options.first { $0.selectedVariantID == recipe.selectedVariantID }

        Menu {
            ForEach(options, id: \.selectedVariantID) { option in
                Button {
                    library.selectVariant(option.selectedVariantID ?? "", for: recipe)
                } label: {
                    if option.selectedVariantID == recipe.selectedVariantID {
                        Label(title(for: option), systemImage: "checkmark")
                    } else {
                        Text(title(for: option))
                    }
                }
            }
        } label: {
            Pill(text: name(of: current ?? recipe), systemImage: "square.stack.3d.up")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
        .fixedSize()
        // Switching mid-download would abandon the files already fetched.
        .disabled(library.downloadStatus(for: recipe)?.isActive == true)
        .help("Choose a variant. Larger variants look better and need more memory.")
    }

    private func name(of option: ModelRecipe) -> String {
        recipe.variants?.first { $0.id == option.selectedVariantID }?.name ?? "Variant"
    }

    /// "Q8 (best quality) · 16.98 GB · Fits", leaving out what is unknown.
    private func title(for option: ModelRecipe) -> String {
        var parts = [name(of: option)]
        if let size = option.totalSizeBytes {
            parts.append(size.formatted(.byteCount(style: .file)))
        }
        switch model.library.fit(for: option) {
        case .comfortable: parts.append("Fits")
        case .tight: parts.append("Tight fit")
        case .tooLarge: parts.append("Too large for this Mac")
        case nil: break
        }
        if model.library.storage.isInstalled(option) {
            parts.append("Installed")
        }
        return parts.joined(separator: " · ")
    }
}
