import KilnCore
import SwiftUI

/// The sidebar's list of saved chats, with archived ones tucked under a toggle.
struct ChatList: View {
    @Environment(AppModel.self) private var model
    @State private var showsArchived = false

    var body: some View {
        let active = model.chats.activeChats
        let archived = model.chats.archivedChats

        if !active.isEmpty || !archived.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if !active.isEmpty {
                        sectionTitle("Chats")
                        ForEach(active) { chat in
                            ChatRow(chat: chat)
                        }
                    }
                    if !archived.isEmpty {
                        archivedToggle(count: archived.count)
                        if showsArchived {
                            ForEach(archived) { chat in
                                ChatRow(chat: chat)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .padding(.top, 14)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }

    private func archivedToggle(count: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { showsArchived.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(showsArchived ? 90 : 0))
                Text("Archived")
                Text("\(count)").foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
