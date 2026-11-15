import Foundation
import ImageIO
import KilnCore
import UniformTypeIdentifiers

/// Files attached to prompts. Each is copied into the app's own folder, so a
/// chat keeps its file after the original is moved or deleted.
struct AttachmentLibrary {
    enum ImportError: Error, LocalizedError {
        case notAccepted([MediaKind])

        var errorDescription: String? {
            guard case .notAccepted(let kinds) = self else { return nil }
            switch kinds {
            case []: return "This model does not take attachments."
            case [.image]: return "That file is not an image Kiln can read. Try a PNG or JPEG."
            default:
                let names = kinds.map { $0.title.lowercased() }.joined(separator: " or ")
                return "This model takes \(names) files, and that file is not one Kiln can read."
            }
        }
    }

    let directory: URL

    /// `~/Library/Application Support/Kiln/attachments`
    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Kiln/attachments", isDirectory: true)
    }

    /// Whether a file is of the given kind, judged by its type.
    private static func file(_ file: URL, is kind: MediaKind) -> Bool {
        UTType(filenameExtension: file.pathExtension)?.conforms(to: kind.contentType) ?? false
    }

    /// Copies a file in and returns where the copy lives. Only files of the given kinds are taken.
    func add(_ file: URL, accepting kinds: [MediaKind]) throws -> URL {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }

        guard let kind = kinds.first(where: { Self.accepts(file, as: $0) }) else {
            throw ImportError.notAccepted(kinds)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = file.pathExtension.isEmpty && kind == .image ? "png" : file.pathExtension.lowercased()
        let copy = directory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        try FileManager.default.copyItem(at: file, to: copy)
        return copy
    }

    func url(named fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Whether a file can be attached as the given kind. An image is judged by
    /// whether it decodes, so one without a file extension still works; other
    /// kinds by their type.
    static func accepts(_ file: URL, as kind: MediaKind) -> Bool {
        guard kind == .image else { return self.file(file, is: kind) }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}
