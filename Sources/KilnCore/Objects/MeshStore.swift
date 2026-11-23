import Foundation

public struct MeshItem: Sendable, Equatable, Identifiable {
    public let url: URL
    public let record: GenerationRecord

    public var id: UUID { record.id }
}

/// Generated 3D objects, stored as GLB files in one folder.
///
/// The folder is the only source of truth, as with the gallery. Each GLB has a
/// JSON file of the same name beside it with the settings it was made with.
public struct MeshStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Kiln/objects`
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Kiln/objects", isDirectory: true)
    }

    @discardableResult
    public func save(_ mesh: GeneratedMesh, record: GenerationRecord) throws -> MeshItem {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = record.createdAt.formatted(
            .iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted)
        )
        let file = directory.appendingPathComponent("\(stamp)-\(record.id.uuidString.prefix(8)).glb")
        try mesh.glb.write(to: file, options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: Self.sidecar(of: file), options: .atomic)
        UserFile.log.notice("Saved a 3D object: \(file.lastPathComponent, privacy: .public)")
        return MeshItem(url: file, record: record)
    }

    /// Every object Kiln wrote into the folder, newest first.
    public func items() -> [MeshItem] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension.lowercased() == "glb" }
            .compactMap { file -> MeshItem? in
                guard let data = try? Data(contentsOf: Self.sidecar(of: file)),
                      let record = try? decoder.decode(GenerationRecord.self, from: data)
                else { return nil }
                return MeshItem(url: file, record: record)
            }
            .sorted { $0.record.createdAt > $1.record.createdAt }
    }

    /// Moves an object, its settings and its picture to the Trash, or erases them when asked to.
    public func delete(_ item: MeshItem, permanently: Bool = false) throws {
        try UserFile.discard(item.url, permanently: permanently)
        try? UserFile.discard(Self.sidecar(of: item.url), permanently: permanently)
        // The picture can be made again from the object, so it is not worth keeping in the Trash.
        try? FileManager.default.removeItem(at: Self.picture(of: item.url))
    }

    /// Where a small picture of an object is kept, for lists. The app makes it; it may not exist yet.
    public static func picture(of object: URL) -> URL {
        object.deletingPathExtension().appendingPathExtension("png")
    }

    private static func sidecar(of file: URL) -> URL {
        file.deletingPathExtension().appendingPathExtension("json")
    }
}
