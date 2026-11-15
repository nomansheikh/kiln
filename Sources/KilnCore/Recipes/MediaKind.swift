/// A kind of content a model takes in or produces.
public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case image
    case audio
    case text
}
