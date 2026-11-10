import Foundation
@testable import KilnCore

/// Replays canned responses and records the requests it was given.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(status: Int, body: String)]
    private(set) var requests: [URLRequest] = []

    init(status: Int = 200, body: String) {
        responses = [(status, body)]
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let next = lock.withLock {
            requests.append(request)
            return responses.count > 1 ? responses.removeFirst() : responses[0]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        return (Data(next.body.utf8), response)
    }
}
