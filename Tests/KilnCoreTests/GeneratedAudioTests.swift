import Foundation
import Testing
@testable import KilnCore

@Suite struct GeneratedAudioTests {
    private func audio(_ samples: [Float32], sampleRate: Int = 4, channels: Int = 1) -> GeneratedAudio {
        GeneratedAudio(sampleRate: sampleRate, channels: channels, samples: samples.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    private func record(createdAt: TimeInterval = 1_800_000_000) -> GenerationRecord {
        GenerationRecord(
            createdAt: Date(timeIntervalSince1970: createdAt), recipeID: "voice", recipeName: "Voice",
            request: GenerationRequest(prompt: "Hello there.", speech: SpeechSettings(voice: "alba")), durationSeconds: 1.5
        )
    }

    @Test func knowsItsLength() {
        let stereo = audio([0, 0, 0, 0, 0, 0, 0, 0], sampleRate: 2, channels: 2)

        #expect(stereo.frameCount == 4)
        #expect(stereo.durationSeconds == 2)
    }

    @Test func writesA16BitWAVFile() throws {
        let wav = try audio([0, 1, -1, 0.5, 2, -.infinity]).wavData()

        #expect(wav.count == 44 + 12)
        #expect(String(decoding: wav[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ")
        // Sample rate 4, mono, 16 bits: 8 bytes per second, 2 bytes per frame.
        #expect(Array(wav[22..<36]) == [1, 0, 4, 0, 0, 0, 8, 0, 0, 0, 2, 0, 16, 0])
        let samples = (0..<6).map { index in
            wav.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 44 + index * 2, as: Int16.self) }
        }
        // Samples beyond full scale are clipped, and one that is not a number is silence.
        #expect(samples == [0, 32767, -32767, 16384, 32767, 0])
    }

    @Test func refusesSamplesThatDoNotAddUp() {
        let broken = GeneratedAudio(sampleRate: 24_000, channels: 1, samples: Data(count: 5))

        #expect(throws: AudioCodecError.invalidSamples) { try broken.wavData() }
        #expect(throws: AudioCodecError.invalidSamples) { try audio([]).wavData() }
    }

    @Test func aWaveformFollowsTheLoudnessOfTheFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-wave-\(UUID().uuidString).wav")
        // Silence, then quiet, then loud: eight samples in each part.
        let samples = [Float32](repeating: 0, count: 8) + [Float32](repeating: 0.25, count: 8) + [Float32](repeating: -0.5, count: 8)
        try audio(samples).wavData().write(to: file)

        let peaks = AudioWaveform.peaks(of: file, count: 3)

        #expect(peaks.count == 3)
        #expect(peaks[0] == 0)
        // Scaled to the loudest part, so the shape fills its height whatever the volume.
        #expect(abs(peaks[1] - 0.5) < 0.01)
        #expect(peaks[2] == 1)
    }

    @Test func aFileThatIsNotAWAVHasNoWaveform() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-wave-\(UUID().uuidString).wav")
        try Data("RIFFnope".utf8).write(to: file)

        #expect(AudioWaveform.peaks(of: file, count: 8).isEmpty)
        #expect(AudioWaveform.peaks(of: file.appendingPathExtension("missing"), count: 8).isEmpty)
        #expect(AudioWaveform.peaks(of: file, count: 0).isEmpty)
    }

    @Test func savedSoundsLoadBackWithTheirSettingsNewestFirst() throws {
        let store = AudioStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("kiln-audio-\(UUID().uuidString)"))
        let old = try store.save(audio([0, 0.5, 0, -0.5]), record: record(createdAt: 1_000))
        let new = try store.save(audio([0, 0.5]), record: record(createdAt: 2_000))
        try Data("not a sound".utf8).write(to: store.directory.appendingPathComponent("stray.wav"))

        let items = store.items()

        // The folder listing may spell the path differently, so items are compared by what they hold.
        #expect(items.map(\.id) == [new.id, old.id])
        #expect(items.map(\.url.lastPathComponent) == [new.url.lastPathComponent, old.url.lastPathComponent])
        #expect(items.map(\.record) == [new.record, old.record])
        #expect(items[1].durationSeconds == 1)
        #expect(items[1].record.request.speech?.voice == "alba")
        #expect(old.url.pathExtension == "wav")

        try store.delete(old, permanently: true)
        #expect(store.items().map(\.id) == [new.id])
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).count == 3)
    }
}
