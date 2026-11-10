import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

public enum HFError: Error, Equatable, LocalizedError {
    case unauthorized
    case accessDenied(repo: String?)
    case notFound
    case rateLimited
    case http(status: Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Hugging Face rejected the access token. Check it in Settings."
        case .accessDenied(let repo):
            if let repo {
                "Access to \(repo) is restricted. Accept its terms on huggingface.co and add your access token in Settings."
            } else {
                "Hugging Face denied access to this resource."
            }
        case .notFound:
            "The model was not found on Hugging Face."
        case .rateLimited:
            "Hugging Face is rate limiting requests. Try again in a minute."
        case .http(let status):
            "Hugging Face returned an error (HTTP \(status))."
        case .invalidResponse:
            "Hugging Face returned a response Kiln could not read."
        }
    }
}

/// Read-only client for the Hugging Face Hub API.
public struct HFClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://huggingface.co")!

    private let transport: any HTTPTransport
    private let baseURL: URL
    private let token: @Sendable () -> String?

    public init(
        transport: any HTTPTransport = URLSession.shared,
        baseURL: URL = HFClient.defaultBaseURL,
        token: @escaping @Sendable () -> String? = { nil }
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.token = token
    }

    /// Text-to-image models matching `query`, most downloaded first.
    public func searchModels(query: String, limit: Int = 30) async throws -> [HFModelSummary] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "pipeline_tag", value: "text-to-image"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "search", value: trimmed))
        }
        return try await get(components.url!, repo: nil)
    }

    /// Repo details including every file with its size and checksum.
    public func modelInfo(repo: String) async throws -> HFModelInfo {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/models").appendingPathComponent(repo),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "blobs", value: "true")]
        return try await get(components.url!, repo: repo)
    }

    /// Checks the stored token and returns the account name.
    public func whoAmI() async throws -> String {
        struct Identity: Decodable { let name: String }
        let identity: Identity = try await get(baseURL.appendingPathComponent("api/whoami-v2"), repo: nil)
        return identity.name
    }

    /// Direct download URL for a file at a revision.
    public static func downloadURL(
        repo: String,
        file: String,
        revision: String?,
        baseURL: URL = HFClient.defaultBaseURL
    ) -> URL {
        baseURL
            .appendingPathComponent(repo)
            .appendingPathComponent("resolve")
            .appendingPathComponent(revision ?? "main")
            .appendingPathComponent(file)
    }

    /// The token must only ever reach Hugging Face itself, never a CDN or mirror.
    public static func authorizationHeader(for url: URL, token: String?) -> String? {
        guard let token, !token.isEmpty, url.scheme == "https", url.host == "huggingface.co" else { return nil }
        return "Bearer \(token)"
    }

    private func get<Response: Decodable>(_ url: URL, repo: String?) async throws -> Response {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorization = Self.authorizationHeader(for: url, token: token()) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HFError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw token() == nil ? HFError.accessDenied(repo: repo) : HFError.unauthorized
        case 403: throw HFError.accessDenied(repo: repo)
        case 404: throw HFError.notFound
        case 429: throw HFError.rateLimited
        default: throw HFError.http(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw HFError.invalidResponse
        }
    }
}
