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
    let width: Int
    let height: Int
    var state: State

    init(id: UUID = UUID(), prompt: String, width: Int, height: Int, state: State = .running) {
        self.id = id
        self.prompt = prompt
        self.width = width
        self.height = height
        self.state = state
    }

    /// A finished turn rebuilt from a saved image.
    init(_ item: GalleryItem) {
        let request = item.record.request
        self.init(id: item.id, prompt: request.prompt, width: request.width, height: request.height, state: .finished(item))
    }

    var image: GalleryItem? {
        if case .finished(let item) = state { item } else { nil }
    }

    /// Width over height of the requested image.
    var aspectRatio: CGFloat {
        CGFloat(max(width, 1)) / CGFloat(max(height, 1))
    }
}
