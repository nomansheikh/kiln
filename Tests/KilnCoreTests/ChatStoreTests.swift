import Foundation
import Testing
@testable import KilnCore

@Suite struct ChatStoreTests {
    let store: ChatStore

    init() {
        store = ChatStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("kiln-chats-\(UUID().uuidString)"))
    }

    private func chat(_ title: String, updatedAt: TimeInterval, archived: Bool = false) -> Chat {
        Chat(
            title: title,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            isArchived: archived,
            turns: [
                ChatTurn(prompt: "a fox", width: 1024, height: 768, outcome: .image(fileName: "fox.png")),
                ChatTurn(prompt: "a lake", width: 512, height: 512, outcome: .failed(message: "Out of memory")),
                ChatTurn(prompt: "a city", width: 512, height: 512, outcome: .cancelled),
            ]
        )
    }

    @Test func savedChatsLoadBackUnchanged() throws {
        let original = chat("Foxes", updatedAt: 2_000, archived: true)

        try store.save(original)

        #expect(store.loadAll() == [original])
    }

    @Test func chatsAreListedMostRecentlyUpdatedFirst() throws {
        try store.save(chat("old", updatedAt: 1_000))
        try store.save(chat("new", updatedAt: 3_000))
        try store.save(chat("middle", updatedAt: 2_000))

        #expect(store.loadAll().map(\.title) == ["new", "middle", "old"])
    }

    @Test func savingAgainReplacesTheChat() throws {
        var renamed = chat("Untitled", updatedAt: 1_000)
        try store.save(renamed)
        renamed.title = "Foxes at dusk"
        renamed.isArchived = true

        try store.save(renamed)

        #expect(store.loadAll() == [renamed])
    }

    @Test func deletingRemovesOnlyThatChat() throws {
        let keep = chat("keep", updatedAt: 1_000)
        let remove = chat("remove", updatedAt: 2_000)
        try store.save(keep)
        try store.save(remove)

        try store.delete(remove.id)
        try store.delete(remove.id) // deleting twice is not an error

        #expect(store.loadAll() == [keep])
    }

    @Test func aDamagedFileDoesNotHideTheOtherChats() throws {
        let good = chat("good", updatedAt: 1_000)
        try store.save(good)
        try Data("{ not json".utf8).write(to: store.directory.appendingPathComponent("broken.json"))
        try Data("notes".utf8).write(to: store.directory.appendingPathComponent("readme.txt"))

        #expect(store.loadAll() == [good])
    }

    @Test func anEmptyOrMissingFolderHasNoChats() {
        #expect(store.loadAll().isEmpty)
    }

    @Test func defaultTitlesAreShortSingleLines() {
        #expect(Chat.defaultTitle(for: "A red fox") == "A red fox")
        #expect(Chat.defaultTitle(for: "  line one\nline two  ") == "line one line two")
        #expect(Chat.defaultTitle(for: "   ") == "New chat")

        let long = "A misty alpine lake at dawn, pine forest reflected in still water, soft golden light"
        let title = Chat.defaultTitle(for: long)
        #expect(title == "A misty alpine lake at dawn, pine forest…")
        #expect(title.count <= 49)

        // A single very long word is cut at the limit instead of being dropped.
        #expect(Chat.defaultTitle(for: String(repeating: "x", count: 80)) == String(repeating: "x", count: 48) + "…")
    }
}
