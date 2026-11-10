import AppKit
import KilnCore
import SwiftUI

/// The context menu of a gallery thumbnail.
struct GalleryItemMenu: View {
    let item: GalleryItem
    let actions: GalleryItemActions

    var body: some View {
        Button {
            actions.reuseSettings(item)
        } label: {
            Label("Reuse Settings", systemImage: "arrow.uturn.backward")
        }
        Button {
            actions.copyImage(item)
        } label: {
            Label("Copy Image", systemImage: "doc.on.doc")
        }
        Button {
            NSPasteboard.general.copyText(item.record.request.prompt)
        } label: {
            Label("Copy Prompt", systemImage: "text.quote")
        }
        Button {
            actions.showInFinder(item)
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
        ShareLink(item: item.url)
        Divider()
        Button(role: .destructive) {
            actions.delete(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
