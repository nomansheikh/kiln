import AppKit
import KilnCore
import Observation

/// Generated 3D objects on disk.
@MainActor
@Observable
final class MeshLibrary {
    private let store: MeshStore
    private(set) var items: [MeshItem] = []

    init(store: MeshStore) {
        self.store = store
        reload()
    }

    var directory: URL { store.directory }

    func reload() {
        items = store.items()
    }

    /// Saves a new object and returns its entry.
    func add(_ mesh: GeneratedMesh, record: GenerationRecord) throws -> MeshItem {
        let item = try store.save(mesh, record: record)
        reload()
        return item
    }

    func delete(_ item: MeshItem) throws {
        try store.delete(item)
        reload()
    }

    func revealInFinder(_ item: MeshItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
