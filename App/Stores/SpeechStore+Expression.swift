import Foundation
import KilnCore

/// The description of the voice or the delivery, for a model that takes one.
extension SpeechStore {
    /// The instruction as the selected model gets it: nil when it takes none or none is written.
    var sentInstruction: String? {
        if let speech = selectedRecipe?.speech, speech.styles != nil {
            return speech.instruction(choosing: styleWords)
        }
        let written = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return selectedRecipe?.speech?.instruction == nil || written.isEmpty ? nil : written
    }

    /// True when the selected model cannot speak until a style is described.
    var needsInstruction: Bool {
        selectedRecipe?.speech?.instruction == .required && sentInstruction == nil
    }

    /// Puts a clip's style back: its words for a model with fixed ones, its description otherwise.
    func restoreStyle(_ sent: String?, for recipe: ModelRecipe) {
        if recipe.speech?.styles != nil {
            styleWords = (sent ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else if recipe.speech?.instruction != nil {
            instruction = sent ?? ""
        }
    }
}
