import Foundation
import Testing
@testable import KilnCore

@Suite struct ReleaseCheckTests {
    private let current = AppVersion("0.2.0")!

    private func check(_ transport: MockTransport) -> ReleaseCheck {
        ReleaseCheck(transport: transport)
    }

    private func release(
        tag: String = "v0.3.0", page: String = "https://github.com/nomansheikh/kiln/releases/tag/v0.3.0",
        draft: Bool = false, prerelease: Bool = false, status: Int = 200
    ) -> MockTransport {
        MockTransport(status: status, body: """
        {"tag_name": "\(tag)", "html_url": "\(page)", "draft": \(draft), "prerelease": \(prerelease), "assets": []}
        """)
    }

    @Test func asksGitHubForTheLatestReleaseWithoutAToken() async throws {
        let transport = release()

        _ = try await check(transport).latestRelease()

        let request = try #require(transport.requests.first)
        #expect(transport.requests.count == 1)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/nomansheikh/kiln/releases/latest")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Kiln")
        #expect(Set((request.allHTTPHeaderFields ?? [:]).keys) == ["Accept", "User-Agent"])
    }

    @Test func reportsANewerRelease() async throws {
        let update = try #require(try await check(release()).update(for: current))

        #expect(update.version == AppVersion("0.3.0"))
        #expect(update.pageURL.absoluteString == "https://github.com/nomansheikh/kiln/releases/tag/v0.3.0")
    }

    @Test(arguments: ["v0.2.0", "0.2", "v0.1.9", "0.1"])
    func reportsNothingForTheSameOrAnOlderRelease(tag: String) async throws {
        #expect(try await check(release(tag: tag)).update(for: current) == nil)
    }

    @Test func ignoresDraftsAndPrereleases() async throws {
        #expect(try await check(release(draft: true)).latestRelease() == nil)
        #expect(try await check(release(prerelease: true)).latestRelease() == nil)
    }

    @Test(arguments: ["nightly", "v0.3.0-beta", ""])
    func ignoresATagThatIsNotAVersion(tag: String) async throws {
        #expect(try await check(release(tag: tag)).latestRelease() == nil)
    }

    @Test(arguments: [
        "https://example.com/nomansheikh/kiln/releases/tag/v0.3.0",
        "https://github.com.example.com/kiln",
        "https://github.com@example.com/kiln",
        "https://api.github.com/kiln",
        "http://github.com/nomansheikh/kiln/releases/tag/v0.3.0",
        "file:///Applications/Kiln.app",
        "",
    ])
    func rejectsAPageOutsideGitHub(page: String) async throws {
        #expect(try await check(release(page: page)).latestRelease() == nil)
        #expect(PublishedRelease(tag: "v0.3.0", page: page) == nil)
    }

    @Test(arguments: [403, 404, 429, 500])
    func failsOnAnHTTPError(status: Int) async {
        await #expect(throws: ReleaseCheckError.http(status: status)) {
            try await check(release(status: status)).update(for: current)
        }
    }

    @Test(arguments: ["", "not json", "[]", "{}", #"{"tag_name": 3, "html_url": "https://github.com/a/b"}"#])
    func failsOnAnUnreadableResponse(body: String) async {
        await #expect(throws: ReleaseCheckError.unreadableResponse) {
            try await check(MockTransport(body: body)).update(for: current)
        }
    }

    @Test func aFailedCheckReportsNoUpdateWhenItsErrorIsDropped() async {
        // How the app calls it: a failure shows nothing.
        let update = try? await check(release(status: 404)).update(for: current)
        #expect(update == nil)
    }

    @Test func isDueAtMostOnceADay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(ReleaseCheck.isDue(lastCheck: nil, now: now))
        #expect(!ReleaseCheck.isDue(lastCheck: now, now: now))
        #expect(!ReleaseCheck.isDue(lastCheck: now.addingTimeInterval(-23 * 60 * 60), now: now))
        #expect(ReleaseCheck.isDue(lastCheck: now.addingTimeInterval(-24 * 60 * 60), now: now))
        #expect(ReleaseCheck.isDue(lastCheck: .distantPast, now: now))
        // A clock that was set back must not stop the checks for good.
        #expect(ReleaseCheck.isDue(lastCheck: now.addingTimeInterval(60), now: now))
    }
}
