import Foundation

public enum ReleaseCheckError: Error, Equatable, LocalizedError {
    case http(status: Int)
    case unreadableResponse

    public var errorDescription: String? {
        switch self {
        case .http(let status): "The latest version could not be looked up (HTTP \(status))."
        case .unreadableResponse: "The latest version could not be read."
        }
    }
}

/// Asks GitHub which release of Kiln is the latest, so the app can say when a
/// newer version exists. It only reads: nothing is downloaded or installed,
/// and the request carries no token and nothing about the user.
public struct ReleaseCheck: Sendable {
    public static let defaultURL = URL(string: "https://api.github.com/repos/nomansheikh/kiln/releases/latest")!
    /// The shortest time between two checks.
    public static let interval: TimeInterval = 24 * 60 * 60

    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool?
        let prerelease: Bool?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft, prerelease
        }
    }

    private static let maximumResponseBytes = 1024 * 1024

    private let url: URL
    private let transport: any HTTPTransport

    public init(url: URL = ReleaseCheck.defaultURL, transport: any HTTPTransport = URLSession.shared) {
        self.url = url
        self.transport = transport
    }

    /// Whether enough time has passed since the last check. A last check in the
    /// future, after the clock was set back, does not block checking.
    public static func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= interval
    }

    /// The latest published release, or nil when it is a draft, a prerelease,
    /// tagged with something that is not a version, or described on a page outside github.com.
    public func latestRelease() async throws -> PublishedRelease? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Kiln", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReleaseCheckError.unreadableResponse }
        guard http.statusCode == 200 else { throw ReleaseCheckError.http(status: http.statusCode) }
        guard data.count <= Self.maximumResponseBytes, let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ReleaseCheckError.unreadableResponse
        }
        guard payload.draft != true, payload.prerelease != true else { return nil }
        return PublishedRelease(tag: payload.tagName, page: payload.htmlURL)
    }

    /// The latest release when it is newer than `current`, otherwise nil.
    public func update(for current: AppVersion) async throws -> PublishedRelease? {
        guard let release = try await latestRelease(), release.version > current else { return nil }
        return release
    }
}
