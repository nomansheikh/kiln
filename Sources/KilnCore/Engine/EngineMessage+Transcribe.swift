import Foundation

/// The request `kiln-whisper` takes.
extension EngineMessage {
    private struct TranscribeCommand: Encodable {
        let type = "transcribe"
        var model: String
        /// File of raw 32-bit float samples, mono, at 16 kHz.
        var audio: String
        /// Words to expect, such as names. Empty for none.
        var prompt: String
        /// File the helper writes the transcript to.
        var output: String
    }

    static func transcribeCommand(model: URL, audio: URL, prompt: String, output: URL) throws -> Data {
        try line(TranscribeCommand(model: model.path, audio: audio.path, prompt: prompt, output: output.path))
    }
}
