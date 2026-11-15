import AppKit
import KilnCore
import Observation
import os

/// Generated sound on disk.
@MainActor
@Observable
final class AudioLibrary {
    private let store: AudioStore
    private(set) var items: [AudioItem] = []

    init(store: AudioStore) {
        self.store = store
        reload()
        // A record of what was there at launch, for when clips go missing.
        Logger(subsystem: "codes.noman.kiln", category: "files")
            .notice("\(self.items.count) clips in \(store.directory.path, privacy: .public)")
    }

    var directory: URL { store.directory }

    func reload() {
        items = store.items()
    }

    /// Saves a new sound and returns its entry.
    func add(_ audio: GeneratedAudio, record: GenerationRecord) throws -> AudioItem {
        let item = try store.save(audio, record: record)
        reload()
        return item
    }

    func delete(_ item: AudioItem) throws {
        try store.delete(item)
        reload()
    }

    func revealInFinder(_ item: AudioItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
