import KilnCore
import SwiftUI

/// The buttons pinned to the bottom of the detail panel.
struct GalleryDetailActionBar: View {
    let item: GalleryItem
    let actions: GalleryItemActions

    var body: some View {
        VStack(spacing: 8) {
            Button {
                actions.reuseSettings(item)
            } label: {
                Label("Reuse Settings", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccentButtonStyle())

            HStack(spacing: 8) {
                Button {
                    actions.copyImage(item)
                } label: {
                    Label("Copy Image", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    actions.showInFinder(item)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(SoftButtonStyle())
            .lineLimit(1)

            HStack(spacing: 8) {
                ShareLink(item: item.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle())

                Button(role: .destructive) {
                    actions.delete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}
