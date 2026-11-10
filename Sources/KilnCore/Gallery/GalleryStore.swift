import Foundation

public struct GalleryItem: Sendable, Equatable, Identifiable {
    public let url: URL
    public let record: GenerationRecord

    public var id: UUID { record.id }
}

/// Past generations, stored as PNG files in one folder.
///
/// The folder is the only source of truth: each PNG embeds its own settings,
/// so there is no database to drift out of sync with the files.
public struct GalleryStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Kiln/gallery`
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Kiln/gallery", isDirectory: true)
    }

    @discardableResult
    public func save(_ image: GeneratedImage, record: GenerationRecord) throws -> GalleryItem {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = record.createdAt.formatted(
            .iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted)
        )
        let file = directory.appendingPathComponent("\(stamp)-\(record.id.uuidString.prefix(8)).png")
        try ImageCodec.pngData(for: image, record: record).write(to: file, options: .atomic)
        return GalleryItem(url: file, record: record)
    }

    /// Every image Kiln wrote into the folder, newest first.
    public func items() -> [GalleryItem] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "png" }
            .compactMap { file in ImageCodec.record(in: file).map { GalleryItem(url: file, record: $0) } }
            .sorted { $0.record.createdAt > $1.record.createdAt }
    }

    public func delete(_ item: GalleryItem) throws {
        try FileManager.default.removeItem(at: item.url)
    }
}
