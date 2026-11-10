import KilnCore
import SwiftUI

struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let item: GalleryItem
    @State private var hovering = false

    var body: some View {
        Button {
            model.show(item)
        } label: {
            HStack(spacing: 8) {
                Thumbnail(url: item.url, maxPixelSize: 96)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(item.record.request.prompt)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                Color.primary.opacity(model.generation.latestImage?.id == item.id && model.selection == .generate ? 0.08 : (hovering ? 0.045 : 0)),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.record.request.prompt)
    }
}
