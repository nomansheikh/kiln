import Foundation
import ImageIO

/// Images attached to prompts. Each is copied into the app's own folder, so a
/// chat keeps its picture after the original file is moved or deleted.
struct AttachmentLibrary {
    enum ImportError: Error, LocalizedError {
        case notAnImage

        var errorDescription: String? {
            "That file is not an image Kiln can read. Try a PNG or JPEG."
        }
    }

    let directory: URL

    /// `~/Library/Application Support/Kiln/attachments`
    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Kiln/attachments", isDirectory: true)
    }

    /// Copies an image in and returns where the copy lives.
    func add(_ file: URL) throws -> URL {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ImportError.notAnImage
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = file.pathExtension.isEmpty ? "png" : file.pathExtension.lowercased()
        let copy = directory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        try FileManager.default.copyItem(at: file, to: copy)
        return copy
    }

    func url(named fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }
}
