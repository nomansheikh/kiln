import Foundation

extension HFModelInfo {
    /// The whole-model file to offer as this repo's one-click download, if it has one.
    ///
    /// Among the files that look like complete checkpoints, the largest that fits
    /// comfortably in `usableBytes` of memory is preferred, since larger usually
    /// means higher precision. If none fits, the smallest is returned so the
    /// caller can still offer it with a warning.
    public func bestStandaloneCheckpoint(usableBytes: Double) -> HFFile? {
        let candidates = weightFiles.filter(\.looksLikeStandaloneCheckpoint)
        let comfortable = candidates.filter { Double($0.sizeBytes ?? 0) <= usableBytes * 0.85 }
        return comfortable.max { ($0.sizeBytes ?? 0) < ($1.sizeBytes ?? 0) }
            ?? candidates.min { ($0.sizeBytes ?? .max) < ($1.sizeBytes ?? .max) }
    }
}
