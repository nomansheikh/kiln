import Foundation
import KilnCore

/// Choosing the model and the file a prompt is sent with.
extension GenerationStore {
    // MARK: - Choosing a model

    /// Selects a model and applies its recommended settings.
    func selectRecipe(_ recipe: ModelRecipe?) {
        draft.select(recipe)
    }

    /// Picks an installed model when the current choice is missing or was deleted.
    func selectDefaultRecipeIfNeeded() {
        if let id = draft.recipeID, library.installedIDs.contains(id) { return }
        let installed = library.installedRecipes
        selectRecipe(installed.first { $0.outputKind == .image } ?? installed.first)
    }

    // MARK: - Attaching a file

    /// Attaches a file for the next prompt, such as an image to rework.
    func attach(_ file: URL) throws {
        draft.attachment = try attachments.add(file, accepting: selectedRecipe?.inputKinds ?? [])
    }

    func removeAttachment() {
        draft.attachment = nil
    }
}
