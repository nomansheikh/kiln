import AppKit
import KilnCore
import Observation

/// Past generations on disk.
@MainActor
@Observable
final class GalleryLibrary {
    private let store: GalleryStore
    private(set) var items: [GalleryItem] = []

    init(store: GalleryStore) {
        self.store = store
        reload()
    }

    var directory: URL { store.directory }

    func reload() {
        items = store.items()
    }

    /// Saves a new image and returns its gallery entry.
    func add(_ image: GeneratedImage, record: GenerationRecord) throws -> GalleryItem {
        let item = try store.save(image, record: record)
        reload()
        return item
    }

    func delete(_ item: GalleryItem) throws {
        try store.delete(item)
        reload()
    }

    func copyToPasteboard(_ item: GalleryItem) {
        guard let image = NSImage(contentsOf: item.url) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    func revealInFinder(_ item: GalleryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
