import Foundation
import os

/// Removing something the user made: a clip, a voice, an image.
public enum UserFile {
    static let log = Logger(subsystem: "codes.noman.kiln", category: "files")

    /// Moves a file to the Trash, so that deleting it can be undone from the
    /// Finder. A file on a volume without a Trash is erased instead.
    /// - Returns: Where the file is now, or nil when it was erased.
    @discardableResult
    public static func discard(_ file: URL, permanently: Bool = false) throws -> URL? {
        if !permanently {
            var moved: NSURL?
            do {
                try FileManager.default.trashItem(at: file, resultingItemURL: &moved)
                log.notice("Moved to the Trash: \(file.lastPathComponent, privacy: .public)")
                return moved as URL?
            } catch CocoaError.featureUnsupported {
                // No Trash on this volume; fall through and erase.
            }
        }
        try FileManager.default.removeItem(at: file)
        log.notice("Erased: \(file.lastPathComponent, privacy: .public)")
        return nil
    }
}
