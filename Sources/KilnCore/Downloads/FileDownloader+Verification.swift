import CryptoKit
import Foundation

extension FileDownloader {
    static func size(of file: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    static func isLarger(_ file: URL, than limit: Int64?) -> Bool {
        guard let limit, let size = size(of: file) else { return false }
        return size > limit
    }

    static func verify(_ file: URL, against item: DownloadItem) throws {
        let actualSize = size(of: file) ?? 0
        if let expected = item.expectedSize, actualSize != expected {
            throw DownloadError.sizeMismatch(expected: expected, actual: actualSize)
        }
        if let expected = item.sha256, try sha256(of: file) != expected.lowercased() {
            throw DownloadError.checksumMismatch
        }
    }

    /// Hex SHA-256 of a file, read in chunks so multi-gigabyte files stay out of memory.
    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
