import Foundation
import KilnCore

/// Turns an engine error into what the thread shows.
enum GenerationFailure {
    static func message(for error: any Error, recipe: ModelRecipe) -> String {
        // A lone file that will not load is almost always one part of a larger
        // model, downloaded by itself from the Hugging Face list.
        if case EngineError.modelLoadFailed = error, recipe.components.count == 1 {
            return """
            \u{201C}\(recipe.name)\u{201D} is not a complete model. It is probably one part of a larger one, \
            such as a text encoder, and cannot generate images by itself. Choose a model from Recommended \
            on the Models screen instead; a recipe downloads every part a model needs.
            """
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
