import KilnCore
import UniformTypeIdentifiers

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

    /// Plural name for menus and messages, such as "Images".
    var title: String {
        switch self {
        case .image: "Images"
        case .audio: "Audio"
        case .text: "Text"
        }
    }

    /// Placeholder of the prompt field for a model that makes this kind.
    var promptPlaceholder: String {
        switch self {
        case .image: "Describe an image"
        case .audio: "Describe the sound, or type what to say"
        case .text: "Ask anything"
        }
    }
}
