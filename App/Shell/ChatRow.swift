import KilnCore
import SwiftUI

/// One chat in the sidebar. Click to open; the menu renames, archives or deletes it.
struct ChatRow: View {
    @Environment(AppModel.self) private var model
    let chat: Chat

    @State private var hovering = false
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var confirmsDelete = false
    @FocusState private var titleFocused: Bool

    private var isOpen: Bool {
        model.generation.chatID == chat.id && model.selection == .generate
    }

    var body: some View {
        HStack(spacing: 4) {
            if isRenaming {
                TextField("Chat name", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { isRenaming = false }
            } else {
                Text(chat.title)
                    .lineLimit(1)
                    .foregroundStyle(chat.isArchived ? .secondary : .primary)
                Spacer(minLength: 0)
                if hovering || isOpen {
                    Menu {
                        ChatMenuItems(chat: chat, rename: beginRename) { confirmsDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 18)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Chat options")
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            Color.primary.opacity(isOpen || isRenaming ? 0.08 : (hovering ? 0.045 : 0)),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming { model.open(chat) }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            ChatMenuItems(chat: chat, rename: beginRename) { confirmsDelete = true }
        }
        .onChange(of: titleFocused) {
            // Clicking elsewhere keeps what was typed, like renaming in Finder.
            if !titleFocused, isRenaming { commitRename() }
        }
        .confirmationDialog("Delete \u{201C}\(chat.title)\u{201D}?", isPresented: $confirmsDelete) {
            Button("Delete Chat", role: .destructive) { model.delete(chat) }
        } message: {
            Text("The chat is removed. Its images stay in the Gallery.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .help(chat.title)
    }

    private func beginRename() {
        draftTitle = chat.title
        isRenaming = true
        titleFocused = true
    }

    private func commitRename() {
        isRenaming = false
        model.chats.rename(chat.id, to: draftTitle)
    }
}

/// The actions offered for a chat, shared by its options menu and context menu.
struct ChatMenuItems: View {
    @Environment(AppModel.self) private var model
    let chat: Chat
    let rename: () -> Void
    let delete: () -> Void

    var body: some View {
        Button("Rename", systemImage: "pencil", action: rename)
        Button(chat.isArchived ? "Unarchive" : "Archive", systemImage: chat.isArchived ? "tray.and.arrow.up" : "archivebox") {
            model.chats.setArchived(!chat.isArchived, for: chat.id)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive, action: delete)
    }
}
