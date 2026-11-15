import Foundation
import KilnCore

/// Choosing the model and the file a prompt is sent with.
extension GenerationStore {
    // MARK: - Choosing a model

    /// Selects a model and applies its recommended settings.
    func selectRecipe(_ recipe: ModelRecipe?) {
        draft.recipeID = recipe?.id
        if let defaults = recipe?.defaults {
            draft.apply(defaults)
        }
        // Keep the chosen voice when the new model has it too.
        if let recipe, draft.voice.map({ !recipe.voices.contains($0) }) ?? true {
            draft.voice = recipe.defaultVoice
        }
        // A language the new model does not offer goes back to "Auto".
        if let language = draft.language, recipe?.languages?.contains(language) != true {
            draft.language = nil
        }
        // An attachment the new model cannot take would only make the next prompt fail.
        if let attachment = draft.attachment, let recipe,
           !recipe.inputKinds.contains(where: { AttachmentLibrary.accepts(attachment, as: $0) }) {
            draft.attachment = nil
        }
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
