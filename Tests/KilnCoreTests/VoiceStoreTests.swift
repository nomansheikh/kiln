import Foundation
import Testing
@testable import KilnCore

@Suite struct VoiceStoreTests {
    let root: URL
    let store: VoiceStore
    let recording: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-voices-\(UUID().uuidString)")
        store = VoiceStore(directory: root.appendingPathComponent("voices"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let samples = (0..<24_000).map { Float32(sin(Double($0) * 0.05) * 0.4) }
        let sound = GeneratedAudio(sampleRate: 24_000, channels: 1, samples: samples.withUnsafeBufferPointer { Data(buffer: $0) })
        recording = root.appendingPathComponent("Me Talking.WAV")
        try sound.wavData().write(to: recording)
    }

    @Test func aVoiceIsACopyOfTheRecordingWithItsNameAndWords() throws {
        let voice = try store.add(recording: recording, name: "  Mine ", transcript: " Hello there.\n")

        #expect(voice.name == "Mine")
        #expect(voice.transcript == "Hello there.")
        #expect(store.voices() == [voice])
        let copy = store.recording(of: voice)
        #expect(copy.deletingLastPathComponent().path == store.directory.path)
        #expect(copy.pathExtension == "wav")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: recording))
        // The original can go; the voice keeps its own copy.
        try FileManager.default.removeItem(at: recording)
        #expect(voice.reference(in: store) == VoiceReference(file: copy, transcript: "Hello there.", name: "Mine"))
    }

    @Test func voicesAreListedByNameAndCanBeChangedAndDeleted() throws {
        var zed = try store.add(recording: recording, name: "Zed", transcript: "")
        let amy = try store.add(recording: recording, name: "amy", transcript: "")
        #expect(store.voices().map(\.name) == ["amy", "Zed"])
        #expect(zed.reference(in: store).transcript == nil)

        zed.name = "Abe"
        zed.transcript = "New words"
        try store.update(zed)
        #expect(store.voices().map(\.name) == ["Abe", "amy"])
        #expect(store.voices().first?.transcript == "New words")

        try store.delete(amy)
        #expect(store.voices().map(\.id) == [zed.id])
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).count == 2)
    }

    @Test func aVoiceNeedsANameAndAudioThatCanBeRead() throws {
        let notes = root.appendingPathComponent("notes.wav")
        try Data("not audio".utf8).write(to: notes)

        #expect(throws: VoiceError.missingName) { try store.add(recording: recording, name: "  ", transcript: "") }
        #expect(throws: EngineError.unreadableAudio) { try store.add(recording: notes, name: "Notes", transcript: "") }
        #expect(store.voices().isEmpty)
    }

    @Test func aDamagedEntryCannotPointOutsideTheFolder() throws {
        let voice = try store.add(recording: recording, name: "Mine", transcript: "")
        let entry = store.directory.appendingPathComponent("\(voice.id.uuidString).json")
        let text = try String(contentsOf: entry, encoding: .utf8).replacingOccurrences(of: voice.id.uuidString + ".wav", with: "../../secret.wav")
        try text.write(to: entry, atomically: true, encoding: .utf8)

        // The recording it names is not in the folder, so the voice is not offered.
        #expect(store.voices().isEmpty)
    }
}
