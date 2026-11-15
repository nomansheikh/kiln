import Foundation

public struct AudioItem: Sendable, Equatable, Identifiable {
    public let url: URL
    public let record: GenerationRecord
    /// Length of the sound in seconds.
    public let durationSeconds: Double

    public var id: UUID { record.id }
}

/// Generated sound, stored as WAV files in one folder.
///
/// The folder is the only source of truth, as with the gallery. A WAV file has
/// no place for settings, so each one has a JSON file of the same name beside it.
public struct AudioStore: Sendable {
    /// What the JSON file beside each WAV holds.
    private struct Sidecar: Codable {
        var record: GenerationRecord
        var durationSeconds: Double
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Kiln/audio`
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Kiln/audio", isDirectory: true)
    }

    @discardableResult
    public func save(_ audio: GeneratedAudio, record: GenerationRecord) throws -> AudioItem {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = record.createdAt.formatted(
            .iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted)
        )
        let file = directory.appendingPathComponent("\(stamp)-\(record.id.uuidString.prefix(8)).wav")
        try audio.wavData().write(to: file, options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(Sidecar(record: record, durationSeconds: audio.durationSeconds))
            .write(to: Self.sidecar(of: file), options: .atomic)
        return AudioItem(url: file, record: record, durationSeconds: audio.durationSeconds)
    }

    /// Every sound Kiln wrote into the folder, newest first.
    public func items() -> [AudioItem] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension.lowercased() == "wav" }
            .compactMap { file -> AudioItem? in
                guard let data = try? Data(contentsOf: Self.sidecar(of: file)),
                      let sidecar = try? decoder.decode(Sidecar.self, from: data)
                else { return nil }
                return AudioItem(url: file, record: sidecar.record, durationSeconds: sidecar.durationSeconds)
            }
            .sorted { $0.record.createdAt > $1.record.createdAt }
    }

    public func delete(_ item: AudioItem) throws {
        try FileManager.default.removeItem(at: item.url)
        try? FileManager.default.removeItem(at: Self.sidecar(of: item.url))
    }

    private static func sidecar(of file: URL) -> URL {
        file.deletingPathExtension().appendingPathExtension("json")
    }
}
