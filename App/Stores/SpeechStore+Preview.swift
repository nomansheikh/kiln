import Foundation
import KilnCore

/// Hearing a voice before using it. A short sample is made the first time a
/// voice is auditioned and kept, so the next time it plays at once.
extension SpeechStore {
    /// Plays a voice's sample, making it first if there is none yet; pauses it if it is playing.
    func togglePreview(of voice: String) {
        guard let recipe = selectedRecipe, recipe.voices.contains(voice) else { return }
        if previewVoice == voice, let previewPlayback {
            previewPlayback.toggle()
            return
        }
        let file = Self.previewFile(recipeID: recipe.id, voice: voice)
        if FileManager.default.fileExists(atPath: file.path) {
            playPreview(file, of: voice)
            return
        }
        guard !isUsingEngine, !isEngineBusyElsewhere() else { return }
        preparingPreview = voice
        Task {
            defer { preparingPreview = nil }
            let name = voice.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? voice
            let request = GenerationRequest(
                prompt: "Hello, I'm \(name). I can read aloud anything you write.", speech: SpeechSettings(voice: voice)
            )
            do {
                for try await event in engine.generate(recipe: recipe, request: request) {
                    guard case .finished(.audio(let sound)) = event else { continue }
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try sound.wavData().write(to: file, options: .atomic)
                    playPreview(file, of: voice)
                }
            } catch is CancellationError {
                // Nothing to report.
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Whether a voice's sample is playing right now.
    func isPreviewPlaying(_ voice: String) -> Bool {
        previewVoice == voice && previewPlayback?.isPlaying == true
    }

    private func playPreview(_ file: URL, of voice: String) {
        let player = AudioPlayback(url: file, duration: 0)
        previewVoice = voice
        previewPlayback = player
        player.play()
    }

    /// `~/Library/Caches/Kiln/voice-samples/<recipe>/<voice>.wav`. Recipe ids and
    /// voice names are restricted to safe characters when a recipe is loaded.
    private static func previewFile(recipeID: String, voice: String) -> URL {
        URL.cachesDirectory
            .appendingPathComponent("Kiln/voice-samples", isDirectory: true)
            .appendingPathComponent(recipeID, isDirectory: true)
            .appendingPathComponent("\(voice).wav")
    }
}
