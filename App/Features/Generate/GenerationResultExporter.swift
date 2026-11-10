import AppKit
import KilnCore
import UniformTypeIdentifiers

/// Saves a copy of a generated image to a place the user picks.
@MainActor
enum GenerationResultExporter {
    /// Runs a save panel and copies the image's PNG to the chosen location.
    static func saveCopy(of item: GalleryItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = item.url.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            // The panel already asked before replacing an existing file.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: item.url, to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
