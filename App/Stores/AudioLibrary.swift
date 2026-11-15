import AppKit
import KilnCore
import Observation

/// Generated sound on disk.
@MainActor
@Observable
final class AudioLibrary {
    private let store: AudioStore
    private(set) var items: [AudioItem] = []

    init(store: AudioStore) {
        self.store = store
        reload()
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
