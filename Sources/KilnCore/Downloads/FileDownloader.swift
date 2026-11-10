import Foundation

/// Resumable HTTP downloads using `Range` requests.
///
/// Data is written to `<destination>.partial`. Only after the size and
/// checksum are verified is the file moved to its destination.
public final class FileDownloader: NSObject, FileDownloading, URLSessionDataDelegate, @unchecked Sendable {
    private enum Outcome {
        case finished
        case rangeNotSatisfiable
    }

    /// Touched only on the session's serial delegate queue once the task is running.
    private final class Transfer {
        let partial: URL
        let offset: Int64
        let onEvent: @Sendable (TransferEvent) -> Void
        let continuation: CheckedContinuation<Outcome, Error>
        var handle: FileHandle?
        var received: Int64 = 0
        var total: Int64?
        var failure: DownloadError?
        var rangeNotSatisfiable = false
        var lastReport = Date.distantPast

        init(
            partial: URL,
            offset: Int64,
            onEvent: @escaping @Sendable (TransferEvent) -> Void,
            continuation: CheckedContinuation<Outcome, Error>
        ) {
            self.partial = partial
            self.offset = offset
            self.onEvent = onEvent
            self.continuation = continuation
        }
    }

    private let authorization: @Sendable (URL) -> String?
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private var session: URLSession!

    /// - Parameter authorization: `Authorization` header value for a URL, or nil to send none.
    ///   Asked again for every redirect so credentials never follow a request to another host.
    public init(
        configuration: URLSessionConfiguration = .default,
        authorization: @escaping @Sendable (URL) -> String? = { _ in nil }
    ) {
        self.authorization = authorization
        super.init()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    public static func partialURL(for destination: URL) -> URL {
        destination.appendingPathExtension("partial")
    }

    /// Records which URL a partial file came from.
    public static func markerURL(for destination: URL) -> URL {
        destination.appendingPathExtension("source")
    }

    public func download(_ item: DownloadItem, onEvent: @escaping @Sendable (TransferEvent) -> Void) async throws {
        let files = FileManager.default
        try files.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = Self.partialURL(for: item.destination)
        let marker = Self.markerURL(for: item.destination)

        // A partial file from another URL, or one that overshot, cannot be continued.
        let source = try? String(contentsOf: marker, encoding: .utf8)
        if source != item.url.absoluteString || Self.isLarger(partial, than: item.expectedSize) {
            try? files.removeItem(at: partial)
        }
        try item.url.absoluteString.write(to: marker, atomically: true, encoding: .utf8)

        if try await transfer(item, to: partial, onEvent: onEvent) == .rangeNotSatisfiable {
            // The server has nothing beyond our offset. That is fine only when
            // the partial file is already complete; otherwise start over.
            if item.expectedSize == nil || Self.size(of: partial) != item.expectedSize {
                try? files.removeItem(at: partial)
                guard try await transfer(item, to: partial, onEvent: onEvent) == .finished else {
                    throw DownloadError.http(status: 416)
                }
            }
        }

        onEvent(.verifying)
        do {
            try Self.verify(partial, against: item)
        } catch let error as DownloadError {
            try? files.removeItem(at: partial)
            try? files.removeItem(at: marker)
            throw error
        }

        if files.fileExists(atPath: item.destination.path) {
            try files.removeItem(at: item.destination)
        }
        try files.moveItem(at: partial, to: item.destination)
        try? files.removeItem(at: marker)
    }

    // MARK: - Transfer

    private func transfer(
        _ item: DownloadItem,
        to partial: URL,
        onEvent: @escaping @Sendable (TransferEvent) -> Void
    ) async throws -> Outcome {
        try Task.checkCancellation()
        let offset = Self.size(of: partial) ?? 0

        var request = URLRequest(url: item.url)
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        if let value = authorization(item.url) {
            request.setValue(value, forHTTPHeaderField: "Authorization")
        }

        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let transfer = Transfer(partial: partial, offset: offset, onEvent: onEvent, continuation: continuation)
                lock.withLock { transfers[task.taskIdentifier] = transfer }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func transfer(for task: URLSessionTask) -> Transfer? {
        lock.withLock { transfers[task.taskIdentifier] }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        var request = request
        request.setValue(request.url.flatMap(authorization), forHTTPHeaderField: "Authorization")
        completionHandler(request)
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let transfer = transfer(for: dataTask), let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        let bodyLength = response.expectedContentLength > 0 ? response.expectedContentLength : nil

        let resumed: Bool
        switch http.statusCode {
        case 200:
            // The server ignored the range and is sending the whole file.
            resumed = false
            transfer.total = bodyLength
        case 206:
            resumed = true
            transfer.total = bodyLength.map { transfer.offset + $0 }
        case 416:
            transfer.rangeNotSatisfiable = true
            completionHandler(.cancel)
            return
        case 401, 403:
            transfer.failure = .accessDenied
            completionHandler(.cancel)
            return
        default:
            transfer.failure = .http(status: http.statusCode)
            completionHandler(.cancel)
            return
        }

        do {
            if !FileManager.default.fileExists(atPath: transfer.partial.path) {
                FileManager.default.createFile(atPath: transfer.partial.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: transfer.partial)
            if resumed {
                try handle.seekToEnd()
                transfer.received = transfer.offset
            } else {
                try handle.truncate(atOffset: 0)
            }
            transfer.handle = handle
            completionHandler(.allow)
        } catch {
            transfer.failure = .network(error.localizedDescription)
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let transfer = transfer(for: dataTask), transfer.failure == nil else { return }
        do {
            try transfer.handle?.write(contentsOf: data)
        } catch {
            transfer.failure = .network(error.localizedDescription)
            dataTask.cancel()
            return
        }
        transfer.received += Int64(data.count)

        let now = Date()
        if now.timeIntervalSince(transfer.lastReport) >= 0.1 {
            transfer.lastReport = now
            transfer.onEvent(.progress(receivedBytes: transfer.received, totalBytes: transfer.total))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let transfer = lock.withLock({ transfers.removeValue(forKey: task.taskIdentifier) }) else { return }
        try? transfer.handle?.close()

        if transfer.rangeNotSatisfiable {
            transfer.continuation.resume(returning: .rangeNotSatisfiable)
        } else if let failure = transfer.failure {
            transfer.continuation.resume(throwing: failure)
        } else if let error {
            if (error as? URLError)?.code == .cancelled {
                transfer.continuation.resume(throwing: CancellationError())
            } else {
                transfer.continuation.resume(throwing: DownloadError.network(error.localizedDescription))
            }
        } else {
            transfer.onEvent(.progress(receivedBytes: transfer.received, totalBytes: transfer.total))
            transfer.continuation.resume(returning: .finished)
        }
    }
}
