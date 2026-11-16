import Foundation
import KilnCore
import Testing

/// The smaller stores: saved chats and the Hugging Face account.
@MainActor
@Suite struct LibraryTests {
    private let fixture: StoreFixture

    init() throws {
        fixture = try StoreFixture()
    }

    private func chat(_ title: String, updated: TimeInterval) -> Chat {
        var chat = Chat(title: title)
        chat.updatedAt = Date(timeIntervalSince1970: updated)
        return chat
    }

    @Test func chatsAreKeptNewestFirstAndSurviveARelaunch() {
        let chats = fixture.chats
        chats.save(chat("Old", updated: 100))
        chats.save(chat("New", updated: 200))

        #expect(chats.chats.map(\.title) == ["New", "Old"])
        #expect(ChatLibrary(store: ChatStore(directory: fixture.root.appendingPathComponent("chats"))).chats.map(\.title) == ["New", "Old"])
    }

    @Test func aChatCanBeRenamedArchivedAndDeleted() throws {
        let chats = fixture.chats
        let first = chat("First", updated: 100)
        chats.save(first)

        chats.rename(first.id, to: "  Foxes ")
        chats.rename(first.id, to: "   ")
        #expect(chats.chat(first.id)?.title == "Foxes")

        chats.setArchived(true, for: first.id)
        #expect(chats.activeChats.isEmpty)
        #expect(chats.archivedChats.map(\.id) == [first.id])

        chats.delete(first.id)
        #expect(chats.chats.isEmpty)
        #expect(ChatStore(directory: fixture.root.appendingPathComponent("chats")).loadAll().isEmpty)
    }

    @Test func theAccountRemembersWhetherATokenIsSaved() throws {
        let tokens = MemoryTokenStore()
        let account = HubAccount(tokenStore: tokens, hub: HFClient())
        #expect(!account.hasToken)

        try account.save("  hf_secret \n")
        #expect(account.hasToken)
        #expect(tokens.read() == "hf_secret")
        #expect(HubAccount(tokenStore: tokens, hub: HFClient()).hasToken)

        try account.remove()
        #expect(!account.hasToken)
        #expect(tokens.read() == nil)
    }
}

/// Holds a token in memory, so that no test touches the Keychain.
final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    func read() -> String? { lock.withLock { token } }
    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func delete() throws { lock.withLock { token = nil } }
}
