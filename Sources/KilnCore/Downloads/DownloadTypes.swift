import Foundation

public struct DownloadItem: Sendable, Equatable {
    public var url: URL
    public var destination: URL
    public var expectedSize: Int64?
    public var sha256: String?

    public init(url: URL, destination: URL, expectedSize: Int64? = nil, sha256: String? = nil) {
        self.url = url
        self.destination = destination
        self.expectedSize = expectedSize
        self.sha256 = sha256
    }
}

public enum TransferEvent: Sendable, Equatable {
    case progress(receivedBytes: Int64, totalBytes: Int64?)
    case verifying
}

public enum DownloadError: Error, Equatable, LocalizedError {
    case accessDenied
    case http(status: Int)
    case network(String)
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch
    case notEnoughDiskSpace(needed: Int64, available: Int64)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Hugging Face denied access to this file. Accept the model's terms on huggingface.co and add your access token in Settings."
        case .http(let status):
            "The download server returned an error (HTTP \(status))."
        case .network(let reason):
            "The download was interrupted: \(reason)"
        case .sizeMismatch(let expected, let actual):
            "The downloaded file is the wrong size (\(actual) bytes instead of \(expected)). It was removed; try again."
        case .checksumMismatch:
            "The downloaded file is corrupted (checksum mismatch). It was removed; try again."
        case .notEnoughDiskSpace(let needed, let available):
            "Not enough disk space: \(needed.formatted(.byteCount(style: .file))) needed, "
                + "\(available.formatted(.byteCount(style: .file))) available."
        }
    }
}

public protocol FileDownloading: Sendable {
    /// Downloads one file, continuing an earlier partial download when there is one.
    /// Cancelling the calling task stops the transfer and keeps the partial file.
    func download(_ item: DownloadItem, onEvent: @escaping @Sendable (TransferEvent) -> Void) async throws
}
