import Foundation

/// A voice the user added: a recording of someone speaking, for a model that
/// can copy a voice.
public struct SavedVoice: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public var name: String
    /// The words spoken in the recording. Empty when they were not given.
    public var transcript: String
    public let createdAt: Date
    /// Name of the recording's file inside the voices folder.
    let fileName: String

    /// How the voice is handed to a model.
    public func reference(in store: VoiceStore) -> VoiceReference {
        VoiceReference(file: store.recording(of: self), transcript: transcript.isEmpty ? nil : transcript, name: name)
    }
}

/// The user's voices, stored as one recording and one JSON file each.
///
/// The folder is the only source of truth, as with the clips.
public struct VoiceStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Kiln/voices`
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Kiln/voices", isDirectory: true)
    }

    /// Every saved voice, by name.
    public func voices() -> [SavedVoice] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> SavedVoice? in
                guard let data = try? Data(contentsOf: file), let voice = try? Self.decoder.decode(SavedVoice.self, from: data),
                      FileManager.default.fileExists(atPath: recording(of: voice).path)
                else { return nil }
                return voice
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func recording(of voice: SavedVoice) -> URL {
        // Only the last part is used, so a damaged entry cannot point outside the folder.
        directory.appendingPathComponent(URL(fileURLWithPath: voice.fileName).lastPathComponent)
    }

    /// Copies a recording into the folder as a new voice. It must be audio Kiln can read.
    @discardableResult
    public func add(recording: URL, name: String, transcript: String) throws -> SavedVoice {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw VoiceError.missingName }
        _ = try AudioSamples.decode(recording, sampleRate: AudioSamples.referenceSampleRate)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let kind = recording.pathExtension.lowercased()
        let isPlain = !kind.isEmpty && kind.count <= 5 && kind.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let voice = SavedVoice(
            id: id, name: name, transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            // Whole seconds, which is what the saved file keeps.
            createdAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)), fileName: "\(id.uuidString).\(isPlain ? kind : "audio")"
        )
        try FileManager.default.copyItem(at: recording, to: self.recording(of: voice))
        try write(voice)
        return voice
    }

    /// Saves a changed name or transcript.
    public func update(_ voice: SavedVoice) throws {
        guard !voice.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoiceError.missingName }
        try write(voice)
    }

    public func delete(_ voice: SavedVoice) throws {
        try FileManager.default.removeItem(at: recording(of: voice))
        try? FileManager.default.removeItem(at: sidecar(of: voice))
    }

    private func write(_ voice: SavedVoice) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(voice).write(to: sidecar(of: voice), options: .atomic)
    }

    private func sidecar(of voice: SavedVoice) -> URL {
        directory.appendingPathComponent("\(voice.id.uuidString).json")
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum VoiceError: Error, Equatable, LocalizedError {
    case missingName

    public var errorDescription: String? {
        switch self {
        case .missingName: "Give the voice a name first."
        }
    }
}
