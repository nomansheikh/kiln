import Foundation

/// Chats on disk, one JSON file each, so a damaged file costs one chat at most.
public struct ChatStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Kiln/chats`
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Kiln/chats", isDirectory: true)
    }

    /// Every readable chat, most recently updated first.
    public func loadAll() -> [Chat] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Chat.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ chat: Chat) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(chat).write(to: file(for: chat.id), options: .atomic)
    }

    public func delete(_ id: UUID) throws {
        let file = file(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    private func file(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
