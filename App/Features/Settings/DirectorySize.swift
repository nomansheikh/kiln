import Foundation

/// Measures how much disk space a folder takes.
enum DirectorySize {
    /// The allocated size of every regular file under `directory`, in bytes.
    ///
    /// Synchronous on purpose: directory enumerators cannot be iterated from
    /// async code. Call it off the main actor.
    static func bytes(in directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
