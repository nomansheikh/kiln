import Foundation
import Testing
@testable import KilnCore

/// Checking an access token with Hugging Face.
@Suite struct HFAccountTests {
    @Test func aValidTokenGivesTheAccountName() async throws {
        let transport = MockTransport(body: #"{"name": "noman", "type": "user"}"#)
        let client = HFClient(transport: transport, token: { "hf_secret" })

        #expect(try await client.whoAmI() == "noman")

        let request = try #require(transport.requests.first)
        #expect(request.url?.path == "/api/whoami-v2")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer hf_secret")
    }

    @Test func aRejectedTokenIsReportedAsSuch() async {
        let client = HFClient(transport: MockTransport(status: 401, body: "{}"), token: { "hf_wrong" })
        await #expect(throws: HFError.unauthorized) { try await client.whoAmI() }
    }

    @Test func withoutATokenTheAnswerIsThatAccessIsDenied() async {
        let client = HFClient(transport: MockTransport(status: 401, body: "{}"))
        await #expect(throws: HFError.accessDenied(repo: nil)) { try await client.whoAmI() }
    }
}
