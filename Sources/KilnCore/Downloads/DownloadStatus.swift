import Foundation

public struct DownloadStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case queued
        case downloading
        case verifying
        case paused
        case completed
        case failed(String)
    }

    public var state: State
    public var receivedBytes: Int64
    public var totalBytes: Int64?
    /// Name of the file being transferred.
    public var currentFile: String?

    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }

    public var isActive: Bool {
        state == .queued || state == .downloading || state == .verifying
    }
}
