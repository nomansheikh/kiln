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
        }
    }

    var symbolName: String {
        switch self {
        case .images: "photo"
        case .speechToText: "waveform"
        case .textToSpeech: "speaker.wave.2"
        case .text: "text.bubble"
        }
    }
}

/// How the app shows and recognises each kind of content.
extension MediaKind {
    /// The file type a file of this kind conforms to.
    var contentType: UTType {
        switch self {
        case .image: .image
        case .audio: .audio
        case .text: .plainText
        }
    }

    /// Name for messages, such as "Images".
    var title: String {
        switch self {
        case .image: "Images"
        case .audio: "Audio"
        case .text: "Text"
        }
    }

    /// Symbol standing for a file of this kind.
    var symbolName: String {
        switch self {
        case .image: "photo"
        case .audio: "waveform"
        case .text: "doc.text"
        }
    }

    /// Placeholder of the prompt field for a model that makes this kind.
    var promptPlaceholder: String {
        switch self {
        case .image: "Describe an image"
        case .audio: "Type what to say"
        case .text: "Ask anything"
        }
    }
}
