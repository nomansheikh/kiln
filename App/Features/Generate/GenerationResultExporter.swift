import AppKit
import KilnCore
import UniformTypeIdentifiers

/// Saves a copy of a generated image or sound to a place the user picks.
@MainActor
enum GenerationResultExporter {
    /// Runs a save panel and copies the image's PNG to the chosen location.
    static func saveCopy(of item: GalleryItem) {
        saveCopy(of: item.url, as: .png)
    }

    /// Runs a save panel and copies the sound's WAV file to the chosen location.
    static func saveCopy(of item: AudioItem) {
        saveCopy(of: item.url, as: .wav)
    }

    private static func saveCopy(of file: URL, as type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = file.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            // The panel already asked before replacing an existing file.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: file, to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
