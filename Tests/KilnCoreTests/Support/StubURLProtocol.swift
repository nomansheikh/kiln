import CryptoKit
import Foundation
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
