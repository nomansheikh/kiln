import Foundation

/// One exchange in the Generate thread: the prompt and what came back.
public struct GenerationTurn: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case running
        case finished(GalleryItem)
        /// Text the model wrote, such as a transcript.
        case text(String)
        /// What was said in the attached recording, with times.
        case transcript(Transcript)
        /// Sound the model made, such as speech.
        case audio(AudioItem)
        case failed(String)
        case cancelled
    }

    public let id: UUID
    public let prompt: String
    /// What the turn asked the model to make.
    public let kind: MediaKind
    /// Size of the requested image. Nil for other kinds of output.
    public let width: Int?
    public let height: Int?
    /// The file attached to the prompt, if any.
    public let attachment: URL?
    public var state: State

    public init(
        id: UUID = UUID(),
        prompt: String,
        kind: MediaKind = .image,
        width: Int?,
        height: Int?,
        attachment: URL? = nil,
        state: State = .running
    ) {
        self.attachment = attachment
        self.id = id
        self.prompt = prompt
        self.kind = kind
        self.width = width
        self.height = height
        self.state = state
    }

    /// A finished turn rebuilt from a saved image.
    public init(_ item: GalleryItem) {
        let request = item.record.request
        self.init(
            id: item.id, prompt: request.prompt, width: request.image?.width, height: request.image?.height, state: .finished(item)
        )
    }

    public var image: GalleryItem? {
        if case .finished(let item) = state { item } else { nil }
    }

    /// Width over height of the requested image. Square when there is no size.
    public var aspectRatio: CGFloat {
        guard let width, let height else { return 1 }
        return CGFloat(max(width, 1)) / CGFloat(max(height, 1))
    }
}
