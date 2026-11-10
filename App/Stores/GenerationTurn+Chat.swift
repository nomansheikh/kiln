import KilnCore

/// Converting thread turns to and from their saved form.
extension GenerationTurn {
    /// A saved turn, with its image looked up in the gallery.
    init(_ turn: ChatTurn, images: [GalleryItem], attachments: AttachmentLibrary) {
        let state: State
        switch turn.outcome {
        case .image(let fileName):
            if let item = images.first(where: { $0.url.lastPathComponent == fileName }) {
                state = .finished(item)
            } else {
                state = .failed("This image is no longer in the Gallery.")
            }
        case .failed(let message):
            state = .failed(message)
        case .cancelled:
            state = .cancelled
        }
        self.init(
            id: turn.id,
            prompt: turn.prompt,
            width: turn.width,
            height: turn.height,
            attachment: turn.attachmentFileName.map(attachments.url(named:)),
            state: state
        )
    }

    /// The form written to disk. A turn still running is saved as stopped,
    /// which is what it will be if the app quits before it finishes.
    var saved: ChatTurn {
        let outcome: ChatTurn.Outcome
        switch state {
        case .finished(let item): outcome = .image(fileName: item.url.lastPathComponent)
        case .failed(let message): outcome = .failed(message: message)
        case .running, .cancelled: outcome = .cancelled
        }
        return ChatTurn(
            id: id,
            prompt: prompt,
            width: width,
            height: height,
            outcome: outcome,
            attachmentFileName: attachment?.lastPathComponent
        )
    }
}
