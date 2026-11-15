/// What a model is used for, in the terms people look for it by.
public enum ModelTask: String, Sendable, CaseIterable {
    case images
    case speechToText
    case textToSpeech
    case text
}

extension ModelRecipe {
    /// The task the recipe's model does, derived from what it takes and makes.
    public var task: ModelTask {
        switch outputKind {
        case .image: .images
        case .audio: .textToSpeech
        case .text: inputKinds.contains(.audio) ? .speechToText : .text
        }
    }
}
