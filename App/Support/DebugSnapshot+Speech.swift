#if DEBUG
import Foundation
import KilnCore

/// Sample turns of a speech-to-text model, for `--sample-speech`.
extension DebugSnapshot {
    /// A finished transcript, a failed turn and a running one, so the thread
    /// of a model that writes text can be seen without one installed.
    static func loadSampleSpeech(into model: AppModel) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-sample-speech")
        func file(_ name: String) -> URL { folder.appendingPathComponent("\(UUID().uuidString)-\(name)") }
        let transcript = Transcript(segments: [
            .init(start: 0, end: 3.2, text: "Thanks everyone for joining."),
            .init(start: 3.2, end: 9.6, text: "Three things today: the release is planned for Thursday,"),
            .init(start: 9.6, end: 14.1, text: "the download page still needs a final review,"),
            .init(start: 14.1, end: 21.8, text: "and we agreed to keep the first version small and ship the rest later."),
            .init(start: 62.4, end: 66, text: "Any questions before we close?"),
        ])
        let turns = [
            GenerationTurn(prompt: "", kind: .text, width: nil, height: nil, attachment: file("Weekly sync.m4a"), state: .transcript(transcript)),
            GenerationTurn(prompt: "Names: Kiln, Qwen", kind: .text, width: nil, height: nil, attachment: file("Interview.mp3"),
                           state: .failed("The attached audio could not be read. Try a WAV, MP3 or M4A file.")),
            GenerationTurn(prompt: "", kind: .text, width: nil, height: nil, attachment: file("Voice memo.wav")),
        ]
        let soFar = Transcript(segments: [
            .init(start: 0, end: 4.1, text: "Note to self: call the printer before noon,"),
            .init(start: 4.1, end: 9.3, text: "and ask whether the proofs can still be changed."),
        ])
        model.generation.loadPreview(
            turns: turns, phase: .running(GenerationProgress(stage: .transcribing, completed: 42, total: 100)), transcript: soFar
        )
    }
}
#endif
