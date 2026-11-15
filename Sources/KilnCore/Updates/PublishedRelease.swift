import Foundation

/// A release of Kiln: its version and the page that describes it.
public struct PublishedRelease: Sendable, Equatable {
    public let version: AppVersion
    public let pageURL: URL

    /// Nil when the tag is not a version, or the page is anywhere but `https://github.com`.
    /// Both come from a server, and the page is opened in the user's browser.
    public init?(tag: String, page: String) {
        guard let version = AppVersion(tag),
              let url = URL(string: page), url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com"
        else { return nil }
        self.version = version
        pageURL = url
    }
}
