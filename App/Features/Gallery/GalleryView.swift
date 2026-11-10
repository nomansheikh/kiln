import AppKit
import KilnCore
import SwiftUI

/// The Gallery screen: every generated image in a grid, with a detail panel
/// for the selected one.
struct GalleryView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: UUID?
    @State private var pendingDelete: GalleryItem?
    @State private var errorMessage: String?

    private var items: [GalleryItem] { model.gallery.items }

    private var selectedItem: GalleryItem? {
        items.first { $0.id == selectedID }
    }

    private var subtitle: String {
        switch items.count {
        case 0: "Everything you generate is kept here"
        case 1: "1 image"
        default: "\(items.count) images"
        }
    }

    private var actions: GalleryItemActions {
        GalleryItemActions(
            reuseSettings: { model.reuseSettings(of: $0) },
            copyImage: { model.gallery.copyToPasteboard($0) },
            showInFinder: { model.gallery.revealInFinder($0) },
            delete: { pendingDelete = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Gallery", subtitle: subtitle) { headerButtons }
            Divider()

            HStack(spacing: 0) {
                Group {
                    if items.isEmpty {
                        GalleryEmptyState { model.selection = .generate }
                    } else {
                        GalleryGrid(items: items, selectedID: $selectedID, actions: actions)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let item = selectedItem {
                    GalleryDetailPanel(item: item, actions: actions, onClose: { selectedID = nil })
                        .frame(width: 320)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.snappy(duration: 0.25), value: selectedItem?.id)
        }
        .confirmationDialog(
            "Delete this image?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) { delete(item) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The image file is removed from the gallery folder. This cannot be undone.")
        }
        .alert(
            "The image could not be deleted",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerButtons: some View {
        Button {
            model.gallery.reload()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(SoftButtonStyle())
        .help("Reload the gallery from disk")
        .accessibilityLabel("Reload")

        Button {
            openGalleryFolder()
        } label: {
            Label("Open Folder", systemImage: "folder")
        }
        .buttonStyle(SoftButtonStyle())
        .help("Open Gallery Folder")
    }

    // MARK: - Actions

    private func delete(_ item: GalleryItem) {
        do {
            try model.deleteGalleryItem(item)
            if selectedID == item.id {
                selectedID = nil
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func openGalleryFolder() {
        let directory = model.gallery.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
