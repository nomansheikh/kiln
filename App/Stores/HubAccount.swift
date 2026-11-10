import Foundation
import KilnCore
import Observation

/// The optional Hugging Face access token.
@MainActor
@Observable
final class HubAccount {
    private let tokenStore: any TokenStore
    private let hub: HFClient
    private(set) var hasToken: Bool

    init(tokenStore: any TokenStore, hub: HFClient) {
        self.tokenStore = tokenStore
        self.hub = hub
        hasToken = tokenStore.read() != nil
    }

    func save(_ token: String) throws {
        try tokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
        hasToken = true
    }

    func remove() throws {
        try tokenStore.delete()
        hasToken = false
    }

    /// Asks Hugging Face who the saved token belongs to.
    func verify() async throws -> String {
        try await hub.whoAmI()
    }
}
