import KilnCore
import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                SidebarToggle(isVisible: $isVisible)
            }
            .padding(.trailing, 10)
            .frame(height: 36) // the traffic lights sit in this strip, centred on the toggle

            VStack(spacing: 1) {
                SidebarRow(title: "New image", symbol: "plus.bubble", shortcut: "\u{2318}N", selected: model.selection == .generate) {
                    model.newImage()
                }
                SidebarRow(title: "Models", symbol: "square.grid.2x2", shortcut: "\u{2318}2", selected: model.selection == .models,
                           badge: model.library.activeDownloads.count) {
                    model.selection = .models
                }
                SidebarRow(title: "Gallery", symbol: "photo.on.rectangle", shortcut: "\u{2318}3", selected: model.selection == .gallery) {
                    model.selection = .gallery
                }
                SidebarRow(title: "Settings", symbol: "gearshape", shortcut: "\u{2318}4", selected: model.selection == .settings) {
                    model.selection = .settings
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            ChatList()

            Spacer(minLength: 8)

            if let download = model.library.activeDownloads.first {
                DownloadSummary(recipe: download.recipe, status: download.status)
                    .padding(10)
            }
        }
    }
}
