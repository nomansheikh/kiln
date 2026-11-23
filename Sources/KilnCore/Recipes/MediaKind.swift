import UniformTypeIdentifiers

/// A kind of content a model takes in or produces.
public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case image
    case audio
    case text
    /// A 3D object: a surface with its colours, as a GLB file.
    case mesh
}

extension MediaKind {
    /// The file type a file of this kind conforms to.
    public var contentType: UTType {
        switch self {
        case .image: .image
        case .audio: .audio
        case .text: .plainText
        case .mesh: UTType(filenameExtension: "glb") ?? .data
        }
    }

    /// Name for messages, such as "Images".
    public var title: String {
        switch self {
        case .image: "Images"
        case .audio: "Audio"
        case .text: "Text"
        case .mesh: "3D objects"
        }
    }
}
