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
        /// Code of the spoken language, or `auto` to detect it.
        var language: String
        /// File the helper writes the transcript to, as JSON.
        var output: String
    }

    static func transcribeCommand(model: URL, audio: URL, prompt: String, language: String? = nil, output: URL) throws -> Data {
        try line(TranscribeCommand(
            model: model.path, audio: audio.path, prompt: prompt, language: language ?? "auto", output: output.path
        ))
    }

    /// The file `kiln-whisper` writes: the segments in order, with times in milliseconds.
    private struct TranscriptFile: Decodable {
        struct Segment: Decodable {
            var startMS: Double
            var endMS: Double
            var text: String

            enum CodingKeys: String, CodingKey {
                case text
                case startMS = "start_ms"
                case endMS = "end_ms"
            }
        }

        var segments: [Segment]
    }

    /// Nil when the file is not what the helper writes.
    static func transcript(from data: Data) -> Transcript? {
        guard let file = try? JSONDecoder().decode(TranscriptFile.self, from: data) else { return nil }
        return Transcript(segments: file.segments.map {
            Transcript.Segment(start: $0.startMS / 1000, end: $0.endMS / 1000, text: $0.text)
        })
    }
}
