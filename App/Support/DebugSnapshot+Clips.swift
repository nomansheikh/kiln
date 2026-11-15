#if DEBUG
import Foundation
import KilnCore

/// Sample clips for the Speech screen, for `--sample-clips`.
extension DebugSnapshot {
    /// With `--sample-clips`, the folder the app uses for generated sound, so a
    /// screenshot shows sample clips instead of the user's own.
    static var sampleAudioDirectory: URL? {
        guard ProcessInfo.processInfo.arguments.contains("--sample-clips") else { return nil }
        return FileManager.default.temporaryDirectory.appendingPathComponent("kiln-sample-clips", isDirectory: true)
    }

    private static let story = """
    The lighthouse keeper had a habit of counting ships. Every evening at six, he climbed the forty-two steps \
    to the lamp room, poured a cup of tea, and wrote the number in a small green notebook.

    On Tuesday there were three: a fishing boat called Marigold, a ferry from Port Ellen, and a grey freighter \
    he did not recognise. On Wednesday there were none, because the fog came in early and stayed until midnight.
    """

    /// Writes a few sample clips and loads the first in the Speech screen's player.
    static func loadSampleClips(into model: AppModel) {
        guard let directory = sampleAudioDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
        let store = AudioStore(directory: directory)
        let clips: [(text: String, voice: String, seconds: Double, age: TimeInterval)] = [
            (story, "alba", 23, 40),
            ("Welcome back. You have three new messages and one reminder for this afternoon.", "george", 6, 900),
            ("Chapter one. It was the best of times, it was the worst of times.", "jane", 5, 7_200),
            ("Thanks for calling. Our opening hours are nine to five, Monday to Friday.", "michael", 5, 90_000),
        ]
        for clip in clips {
            let record = GenerationRecord(
                createdAt: Date().addingTimeInterval(-clip.age), recipeID: "sample", recipeName: "PocketTTS English",
                request: GenerationRequest(prompt: clip.text, speech: SpeechSettings(voice: clip.voice))
            )
            _ = try? store.save(speechLikeSound(seconds: clip.seconds, seed: clip.voice.count), record: record)
        }
        model.audio.reload()
        model.speech.loadPreview(text: story, current: model.audio.items.first)
        // Part-way through, so the played part of the waveform is visible.
        model.speech.playback?.seek(to: 8)
    }

    /// A tone that rises and falls in bursts with short gaps, so its waveform
    /// has the shape of speech. It is not meant to be listened to.
    private static func speechLikeSound(seconds: Double, seed: Int) -> GeneratedAudio {
        let rate = 24_000
        let count = Int(seconds * Double(rate))
        var samples = [Float32](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / Double(rate)
            // Syllables about four times a second, words about once, with a pause between phrases.
            let syllable = pow(abs(sin(time * 4.1 * .pi + Double(seed))), 1.5)
            let word = 0.45 + 0.55 * abs(sin(time * 0.9 * .pi + Double(seed) * 0.7))
            let phrase = sin(time * 0.33 * .pi + Double(seed)) > -0.82 ? 1.0 : 0.04
            // Each syllable gets its own loudness, as stressed and unstressed ones do.
            let stress = 0.35 + 0.65 * abs(sin(floor(time * 4.1 + Double(seed) / .pi) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
            samples[index] = Float32(sin(time * 2 * .pi * 180) * syllable * word * phrase * stress * 0.8)
        }
        return GeneratedAudio(sampleRate: rate, channels: 1, samples: samples.withUnsafeBufferPointer { Data(buffer: $0) })
    }
}
#endif
