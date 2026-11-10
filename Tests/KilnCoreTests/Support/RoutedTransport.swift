import Foundation
@testable import KilnCore

/// Answers each URL with its own canned response; anything else is a 404.
final class RoutedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: (status: Int, body: Data)] = [:]
    private(set) var requestedURLs: [String] = []

    func route(_ url: String, status: Int = 200, body: Data) {
        lock.withLock { routes[url] = (status, body) }
    }

    func route(_ url: String, status: Int = 200, body: String) {
        route(url, status: status, body: Data(body.utf8))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!.absoluteString
        let reply = lock.withLock {
            requestedURLs.append(url)
            return routes[url] ?? (404, Data())
        }
        return (reply.body, HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!)
    }
}
