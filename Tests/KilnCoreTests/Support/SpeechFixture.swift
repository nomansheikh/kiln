import AVFoundation
import Foundation
@testable import KilnCore

/// A models folder with one installed speech-to-text recipe, a short audio
/// file, and fake helpers to run them against.
struct SpeechFixture {
    let root: URL
    let storage: ModelStorage
    let recipe: ModelRecipe
    /// One second of a 440 Hz tone, stereo at 44.1 kHz.
    let audio: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-speech-tests-\(UUID().uuidString)")
        storage = ModelStorage(root: root.appendingPathComponent("models"))
        recipe = ModelRecipe(
            id: "speech",
            name: "Speech",
            engine: WhisperCppEngine.engineID,
            components: [.init(role: .model, repo: "owner/name", file: "ggml-model.bin")],
            output: .text,
            accepts: [.audio],
            defaults: nil
        )
        let model = storage.url(for: recipe.components[0])
        try FileManager.default.createDirectory(at: model.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: model)

        audio = root.appendingPathComponent("tone.wav")
        try Self.writeTone(to: audio)
    }

    private static func writeTone(to file: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for channel in 0..<2 {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<44_100 {
                samples[frame] = sin(2 * .pi * 440 * Float(frame) / 44_100) * 0.5
            }
        }
        try AVAudioFile(forWriting: file, settings: format.settings).write(from: buffer)
    }

    /// An engine whose helper is a shell script. `body` runs once per transcribe
    /// request, with `$audio` and `$output` holding the paths from the request.
    func engine(onTranscribe body: String, grace: Duration = .seconds(3)) throws -> WhisperCppEngine {
        let script = """
        #!/bin/sh
        echo '{"type":"ready","version":"test","commit":""}'
        while IFS= read -r line; do
          case "$line" in
            *'"type":"transcribe"'*)
              audio=$(printf '%s' "$line" | sed -E 's/.*"audio":"([^"]*)".*/\\1/')
              output=$(printf '%s' "$line" | sed -E 's/.*"output":"([^"]*)".*/\\1/')
              \(body)
              ;;
          esac
        done
        """
        let helper = root.appendingPathComponent("helper-\(UUID().uuidString).sh")
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        return WhisperCppEngine(
            helperURL: helper,
            storage: storage,
            scratchDirectory: root.appendingPathComponent("scratch"),
            cancelGracePeriod: grace
        )
    }
}
