import Foundation

/// The request `kiln-audio` takes.
extension EngineMessage {
    private struct SpeakCommand: Encodable {
        let type = "speak"
        var model: String
        /// audio.cpp's name for the kind of model, such as `pocket_tts`.
        var family: String
        var text: String
        var voice: String?
        /// File the helper writes the sound to, as raw interleaved 32-bit floats.
        var output: String
    }

    static func speakCommand(model: URL, family: String, text: String, voice: String?, output: URL) throws -> Data {
        try line(SpeakCommand(model: model.path, family: family, text: text, voice: voice, output: output.path))
    }
}
