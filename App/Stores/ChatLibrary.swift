import Foundation
import KilnCore
import Observation

/// The saved chats shown in the sidebar.
@MainActor
@Observable
final class ChatLibrary {
    private let store: ChatStore
    /// Every chat, most recently updated first.
    private(set) var chats: [Chat] = []

    init(store: ChatStore) {
        self.store = store
        chats = store.loadAll()
    }

    var activeChats: [Chat] { chats.filter { !$0.isArchived } }
    var archivedChats: [Chat] { chats.filter(\.isArchived) }

    func chat(_ id: UUID) -> Chat? {
        chats.first { $0.id == id }
    }

    /// Adds the chat or replaces the stored copy, then writes it to disk.
    func save(_ chat: Chat) {
        chats.removeAll { $0.id == chat.id }
        chats.append(chat)
        chats.sort { $0.updatedAt > $1.updatedAt }
        try? store.save(chat)
    }

    /// Renames a chat. An empty name is ignored.
    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var chat = chat(id), chat.title != trimmed else { return }
        chat.title = trimmed
        save(chat)
    }

    func setArchived(_ archived: Bool, for id: UUID) {
        guard var chat = chat(id), chat.isArchived != archived else { return }
        chat.isArchived = archived
        save(chat)
    }

    /// Deletes the chat. Its images stay in the Gallery.
    func delete(_ id: UUID) {
        chats.removeAll { $0.id == id }
        try? store.delete(id)
    }
}
