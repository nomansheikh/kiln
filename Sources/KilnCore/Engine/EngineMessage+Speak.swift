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
        /// Language code, when the user chose one.
        var language: String?
        /// Settings by the names audio.cpp gives them, such as `instruct`.
        var options: [String: String]?
        /// `metal` for the GPU or `cpu`.
        var backend: String
        /// File the helper writes the sound to, as raw interleaved 32-bit floats.
        var output: String
    }

    static func speakCommand(
        model: URL, family: String, text: String, voice: String?, language: String? = nil, instruction: String? = nil,
        onGPU: Bool = true, output: URL
    ) throws -> Data {
        try line(SpeakCommand(
            model: model.path, family: family, text: text, voice: voice, language: language,
            options: instruction.map { ["instruct": $0] }, backend: onGPU ? "metal" : "cpu", output: output.path
        ))
    }
}
