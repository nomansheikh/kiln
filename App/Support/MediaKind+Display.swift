import KilnCore
import UniformTypeIdentifiers

extension ModelTask {
    /// Name of the task in filters and menus.
    var title: String {
        switch self {
        case .images: "Images"
        case .speechToText: "Speech to text"
        case .textToSpeech: "Text to speech"
        case .text: "Text"
        case .objects: "3D objects"
        }
    }

    var symbolName: String {
        switch self {
        case .images: "photo"
        case .speechToText: "waveform"
        case .textToSpeech: "speaker.wave.2"
        case .text: "text.bubble"
        case .objects: "cube"
        }
    }
}

/// How the app shows and recognises each kind of content.
extension MediaKind {
    /// Symbol standing for a file of this kind.
    var symbolName: String {
        switch self {
        case .image: "photo"
        case .audio: "waveform"
        case .text: "doc.text"
        case .mesh: "cube"
        }
    }

    /// Placeholder of the prompt field for a model that makes this kind.
    var promptPlaceholder: String {
        switch self {
        case .image: "Describe an image"
        case .audio: "Type what to say"
        case .text: "Ask anything"
        case .mesh: "Attach a picture of one object"
        }
    }
}
