import CryptoKit
import Foundation
import Testing
@testable import KilnCore

/// Serves canned HTTP responses to a `URLSession`, keyed by host so tests can run in parallel.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        /// Fail the connection after sending this many body bytes.
        var failAfter: Int?
        var redirect: URL?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: (URLRequest) -> Reply] = [:]
    nonisolated(unsafe) private static var recorded: [String: [URLRequest]] = [:]

    static func register(host: String, handler: @escaping (URLRequest) -> Reply) {
        lock.withLock { handlers[host] = handler }
    }

    static func requests(host: String) -> [URLRequest] {
        lock.withLock { recorded[host] ?? [] }
    }

    static func session() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let host = request.url?.host ?? ""
        let handler = Self.lock.withLock {
            Self.recorded[host, default: []].append(request)
            return Self.handlers[host]
        }
        guard let reply = handler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        if let redirect = reply.redirect {
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": redirect.absoluteString])!
            var next = request
            next.url = redirect
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            return
        }

        var headers = reply.headers
        headers["Content-Length"] = String(reply.body.count)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let failAfter = reply.failAfter {
            client?.urlProtocol(self, didLoad: reply.body.prefix(failAfter))
            // URLSession drops the body it has buffered if the failure arrives in the same turn.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
        } else {
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    /// Serves `content` like a file server that understands `Range: bytes=N-`.
    static func fileServer(_ content: Data, failFirstRequestAfter: Int? = nil) -> (URLRequest) -> Reply {
        let failures = Counter(failFirstRequestAfter == nil ? 0 : 1)
        return { request in
            var reply = Reply(body: content)
            if let range = request.value(forHTTPHeaderField: "Range"),
               let offset = Int(range.dropFirst("bytes=".count).dropLast()) {
                guard offset < content.count else { return Reply(status: 416) }
                reply = Reply(status: 206, body: content.suffix(from: offset))
            }
            if failures.take() {
                reply.failAfter = failFirstRequestAfter
            }
            return reply
        }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int

    init(_ count: Int) { remaining = count }

    /// True while there is budget left, consuming one unit.
    func take() -> Bool {
        lock.withLock {
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
    }
}

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [TransferEvent] = []

    func append(_ event: TransferEvent) { lock.withLock { events.append(event) } }
    var all: [TransferEvent] { lock.withLock { events } }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@Suite struct FileDownloaderTests {
    let directory: URL
    let host = "\(UUID().uuidString.lowercased()).test"
    let content = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var url: URL { URL(string: "https://\(host)/owner/repo/resolve/abc/model.gguf")! }
    private var destination: URL { directory.appendingPathComponent("nested/model.gguf") }
    private var partial: URL { FileDownloader.partialURL(for: destination) }

    private func item(size: Int64? = nil, sha256: String? = nil) -> DownloadItem {
        DownloadItem(url: url, destination: destination, expectedSize: size ?? Int64(content.count), sha256: sha256 ?? sha256Hex(content))
    }

    private func exists(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path)
    }

    @Test func downloadsVerifiesAndMovesIntoPlace() async throws {
        StubURLProtocol.register(host: host, handler: StubURLProtocol.fileServer(content))
        let log = EventLog()

        try await FileDownloader(configuration: StubURLProtocol.session()).download(item(), onEvent: log.append)

        #expect(try Data(contentsOf: destination) == content)
        #expect(!exists(partial))
        #expect(!exists(FileDownloader.markerURL(for: destination)))
        #expect(log.all.contains(.progress(receivedBytes: Int64(content.count), totalBytes: Int64(content.count))))
        #expect(log.all.last == .verifying)
        #expect(StubURLProtocol.requests(host: host).first?.value(forHTTPHeaderField: "Range") == nil)
    }

    @Test func resumesAnInterruptedDownloadWithARangeRequest() async throws {
        StubURLProtocol.register(host: host, handler: StubURLProtocol.fileServer(content, failFirstRequestAfter: 80_000))
        let downloader = FileDownloader(configuration: StubURLProtocol.session())

        await #expect(throws: DownloadError.self) { try await downloader.download(item(), onEvent: { _ in }) }
        #expect(try Data(contentsOf: partial) == content.prefix(80_000))
        #expect(!exists(destination))

        try await downloader.download(item(), onEvent: { _ in })

        #expect(try Data(contentsOf: destination) == content)
        let ranges = StubURLProtocol.requests(host: host).map { $0.value(forHTTPHeaderField: "Range") }
        #expect(ranges == [nil, "bytes=80000-"])
    }

    @Test func restartsWhenTheServerIgnoresTheRange() async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xFF, count: 500).write(to: partial)
        try url.absoluteString.write(to: FileDownloader.markerURL(for: destination), atomically: true, encoding: .utf8)
        let body = content
        StubURLProtocol.register(host: host) { _ in .init(status: 200, body: body) }

        try await FileDownloader(configuration: StubURLProtocol.session()).download(item(), onEvent: { _ in })

        #expect(try Data(contentsOf: destination) == content)
    }

    @Test func discardsAPartialFileFromADifferentURL() async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xFF, count: 500).write(to: partial)
        try "https://elsewhere.test/other.gguf".write(to: FileDownloader.markerURL(for: destination), atomically: true, encoding: .utf8)
        StubURLProtocol.register(host: host, handler: StubURLProtocol.fileServer(content))

        try await FileDownloader(configuration: StubURLProtocol.session()).download(item(), onEvent: { _ in })

        #expect(try Data(contentsOf: destination) == content)
        #expect(StubURLProtocol.requests(host: host).first?.value(forHTTPHeaderField: "Range") == nil)
    }

    @Test func finishesWhenThePartialFileIsAlreadyComplete() async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: partial)
        try url.absoluteString.write(to: FileDownloader.markerURL(for: destination), atomically: true, encoding: .utf8)
        StubURLProtocol.register(host: host, handler: StubURLProtocol.fileServer(content))

        try await FileDownloader(configuration: StubURLProtocol.session()).download(item(), onEvent: { _ in })

        #expect(try Data(contentsOf: destination) == content)
        #expect(StubURLProtocol.requests(host: host).count == 1)
    }

    @Test func rejectsACorruptedFileAndRemovesIt() async throws {
        StubURLProtocol.register(host: host, handler: StubURLProtocol.fileServer(content))
        let wrongHash = String(repeating: "0", count: 64)

        await #expect(throws: DownloadError.checksumMismatch) {
            try await FileDownloader(configuration: StubURLProtocol.session()).download(item(sha256: wrongHash), onEvent: { _ in })
        }
        #expect(!exists(destination))
        #expect(!exists(partial))
    }

    @Test func rejectsAFileOfTheWrongSize() async throws {
        StubURLProtocol.register(host: host, handler: StubURLProtocol.fileServer(content.prefix(1_000)))

        await #expect(throws: DownloadError.sizeMismatch(expected: Int64(content.count), actual: 1_000)) {
            try await FileDownloader(configuration: StubURLProtocol.session()).download(item(), onEvent: { _ in })
        }
        #expect(!exists(destination))
    }

    @Test(arguments: [(401, DownloadError.accessDenied), (403, .accessDenied), (404, .http(status: 404)), (500, .http(status: 500))])
    func mapsHTTPFailures(status: Int, expected: DownloadError) async throws {
        StubURLProtocol.register(host: host) { _ in .init(status: status) }

        await #expect(throws: expected) {
            try await FileDownloader(configuration: StubURLProtocol.session()).download(item(), onEvent: { _ in })
        }
        #expect(!exists(destination))
    }

    @Test func cancellingTheTaskStopsTheDownload() async throws {
        StubURLProtocol.register(host: host, handler: StubURLProtocol.fileServer(content))
        let downloader = FileDownloader(configuration: StubURLProtocol.session())
        let download = item()

        let task = Task { try await downloader.download(download, onEvent: { _ in }) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!exists(destination))
    }

    @Test func credentialsAreDroppedWhenRedirectedToAnotherHost() async throws {
        let cdnHost = "cdn-\(host)"
        let cdnURL = URL(string: "https://\(cdnHost)/blob")!
        StubURLProtocol.register(host: host) { _ in .init(redirect: cdnURL) }
        StubURLProtocol.register(host: cdnHost, handler: StubURLProtocol.fileServer(content))
        let origin = host
        let downloader = FileDownloader(configuration: StubURLProtocol.session()) { url in
            url.host == origin ? "Bearer hf_secret" : nil
        }

        try await downloader.download(item(), onEvent: { _ in })

        #expect(StubURLProtocol.requests(host: host).first?.value(forHTTPHeaderField: "Authorization") == "Bearer hf_secret")
        #expect(StubURLProtocol.requests(host: cdnHost).first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(try Data(contentsOf: destination) == content)
    }

    @Test func hashesFilesInChunks() throws {
        let file = directory.appendingPathComponent("blob")
        try content.write(to: file)
        #expect(try FileDownloader.sha256(of: file) == sha256Hex(content))
    }
}
