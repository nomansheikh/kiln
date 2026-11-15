import Foundation
import KilnCore

/// One exchange in the Generate thread: the prompt and what came back.
struct GenerationTurn: Identifiable, Equatable {
    enum State: Equatable {
        case running
        case finished(GalleryItem)
        case failed(String)
        case cancelled
    }

    let id: UUID
    let prompt: String
    /// Size of the requested image. Nil for other kinds of output.
    let width: Int?
    let height: Int?
    /// The file attached to the prompt, if any.
    let attachment: URL?
    var state: State

    init(id: UUID = UUID(), prompt: String, width: Int?, height: Int?, attachment: URL? = nil, state: State = .running) {
        self.attachment = attachment
        self.id = id
        self.prompt = prompt
        self.width = width
        self.height = height
        self.state = state
    }

    /// A finished turn rebuilt from a saved image.
    init(_ item: GalleryItem) {
        let request = item.record.request
        self.init(
            id: item.id, prompt: request.prompt, width: request.image?.width, height: request.image?.height, state: .finished(item)
        )
    }

    var image: GalleryItem? {
        if case .finished(let item) = state { item } else { nil }
    }

    /// Width over height of the requested image. Square when there is no size.
    var aspectRatio: CGFloat {
        guard let width, let height else { return 1 }
        return CGFloat(max(width, 1)) / CGFloat(max(height, 1))
    }
}
