import Foundation
import Testing
@testable import KilnCore

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
