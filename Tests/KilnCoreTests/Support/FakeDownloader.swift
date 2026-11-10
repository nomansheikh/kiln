import Foundation
@testable import KilnCore

/// Writes files instantly, or blocks until released so tests can observe mid-download states.
final class FakeDownloader: FileDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]
    private var started: [String] = []
    private var failures: [String: DownloadError] = [:]
    private var blocked: Set<String> = []

    var startedFiles: [String] { lock.withLock { started } }

    func block(_ name: String) { lock.withLock { _ = blocked.insert(name) } }
    func fail(_ name: String, with error: DownloadError) { lock.withLock { failures[name] = error } }
    func succeedFromNowOn(_ name: String) { lock.withLock { failures[name] = nil } }

    func release(_ name: String) {
        lock.withLock {
            blocked.remove(name)
            return gates.removeValue(forKey: name)
        }?.resume()
    }

    func download(_ item: DownloadItem, onEvent: @escaping @Sendable (TransferEvent) -> Void) async throws {
        let name = item.destination.lastPathComponent
        let size = item.expectedSize ?? 10
        lock.withLock { started.append(name) }
        onEvent(.progress(receivedBytes: size / 2, totalBytes: size))

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let wait = lock.withLock {
                    guard blocked.contains(name), !Task.isCancelled else { return false }
                    gates[name] = continuation
                    return true
                }
                if !wait { continuation.resume() }
            }
        } onCancel: {
            lock.withLock { gates.removeValue(forKey: name) }?.resume()
        }
        try Task.checkCancellation()
        if let failure = lock.withLock({ failures[name] }) { throw failure }

        onEvent(.verifying)
        try FileManager.default.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: Int(size)).write(to: item.destination)
    }
}
