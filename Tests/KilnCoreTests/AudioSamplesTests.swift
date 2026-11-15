import Foundation
import Testing
@testable import KilnCore

@Suite struct AudioSamplesTests {
    let fixture: SpeechFixture

    init() throws {
        fixture = try SpeechFixture()
    }

    @Test func decodesToSixteenKilohertzMono() throws {
        // The fixture is one second of stereo at 44.1 kHz.
        let samples = try AudioSamples.decode(fixture.audio)

        #expect(abs(samples.count - 16_000) < 200)
        // A half-amplitude tone stays a half-amplitude tone when the two channels are mixed.
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.4 && peak < 0.6)
    }

    @Test func rejectsFilesThatAreNotAudio() throws {
        let file = fixture.root.appendingPathComponent("notes.mp3")
        try Data("not audio".utf8).write(to: file)

        #expect(throws: EngineError.unreadableAudio) { try AudioSamples.decode(file) }
        #expect(throws: EngineError.unreadableAudio) {
            try AudioSamples.decode(fixture.root.appendingPathComponent("missing.wav"))
        }
    }
}
