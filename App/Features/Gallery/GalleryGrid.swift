import AppKit
import KilnCore
import SwiftUI

/// The scrolling grid of thumbnails. A click selects, a double-click opens the
/// image, and a click on the empty background clears the selection.
struct GalleryGrid: View {
    let items: [GalleryItem]
    @Binding var selectedID: UUID?
    let actions: GalleryItemActions

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    GalleryCell(
                        item: item,
                        isSelected: item.id == selectedID,
                        onReuse: { actions.reuseSettings(item) },
                        onCopy: { actions.copyImage(item) }
                    )
                    .onTapGesture { selectedID = item.id }
                    // Simultaneous, so a single click selects without waiting for a second one.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { NSWorkspace.shared.open(item.url) })
                    .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                    .contextMenu { GalleryItemMenu(item: item, actions: actions) }
                }
            }
            .padding(24)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = nil }
            }
        }
    }
}
