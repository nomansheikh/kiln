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
        /// A recording of the voice to speak in, as raw mono 32-bit floats, and its sample rate.
        var voiceAudio: String?
        var voiceSampleRate: Int?
        /// Language code, when the user chose one.
        var language: String?
        /// Settings by the names audio.cpp gives them, such as `instruct`.
        var options: [String: String]?
        /// `metal` for the GPU or `cpu`.
        var backend: String
        /// File the helper writes the sound to, as raw interleaved 32-bit floats.
        var output: String

        enum CodingKeys: String, CodingKey {
            case type, model, family, text, voice, language, options, backend, output
            case voiceAudio = "voice_audio"
            case voiceSampleRate = "voice_sample_rate"
        }
    }

    static func speakCommand(
        model: URL, family: String, text: String, voice: String?, voiceAudio: (file: URL, sampleRate: Int)? = nil,
        language: String? = nil, options: [String: String] = [:], onGPU: Bool = true, output: URL
    ) throws -> Data {
        try line(SpeakCommand(
            model: model.path, family: family, text: text, voice: voice,
            voiceAudio: voiceAudio?.file.path, voiceSampleRate: voiceAudio?.sampleRate, language: language,
            options: options.isEmpty ? nil : options, backend: onGPU ? "metal" : "cpu", output: output.path
        ))
    }
}
