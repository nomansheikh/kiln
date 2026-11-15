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
        let transcript = """
        Thanks everyone for joining. Three things today: the release is planned for Thursday, the download \
        page still needs a final review, and we agreed to keep the first version small and ship the rest later.
        """
        let turns = [
            GenerationTurn(prompt: "", kind: .text, width: nil, height: nil, attachment: file("Weekly sync.m4a"), state: .text(transcript)),
            GenerationTurn(prompt: "Names: Kiln, Qwen", kind: .text, width: nil, height: nil, attachment: file("Interview.mp3"),
                           state: .failed("The attached audio could not be read. Try a WAV, MP3 or M4A file.")),
            GenerationTurn(prompt: "", kind: .text, width: nil, height: nil, attachment: file("Voice memo.wav")),
        ]
        model.generation.loadPreview(turns: turns, phase: .running(GenerationProgress(stage: .transcribing, completed: 42, total: 100)))
    }
}
#endif
