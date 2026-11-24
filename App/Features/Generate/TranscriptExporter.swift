import AppKit
import KilnCore
import UniformTypeIdentifiers

/// Saves a transcript to a place the user picks, as plain text or as subtitles.
@MainActor
enum TranscriptExporter {
    /// - Parameter format: The subtitle format, or nil for the words alone.
    static func save(_ transcript: Transcript, as format: Transcript.SubtitleFormat?, named name: String) {
        let ending = format?.rawValue ?? "txt"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ending) ?? .plainText]
        panel.nameFieldStringValue = "\(name).\(ending)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let contents = format.map(transcript.subtitles) ?? transcript.text + "\n"
            try contents.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
