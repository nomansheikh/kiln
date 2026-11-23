import KilnCore
import SwiftUI

/// The row of quiet actions under the object on the stage.
struct ObjectsActions: View {
    @Environment(AppModel.self) private var model
    let item: MeshItem

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(MeshExporter.Format.allCases) { format in
                    Button(format.title) { MeshExporter.save(item, as: format) }
                }
            } label: {
                MessageActionIcon(systemImage: "arrow.down.to.line")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerCursor()
            .hint("Save as GLB, USDZ or OBJ")
            ShareLink(item: item.url) {
                MessageActionIcon(systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PressableButtonStyle())
            .hint("Share")
            MessageActionButton(systemImage: "folder", help: "Show in Finder") {
                model.objects.revealInFinder(item)
            }
            MessageActionButton(systemImage: "arrow.uturn.backward", help: "Use this picture and settings again", confirms: true) {
                model.studio.reuse(item)
            }
            MessageActionButton(systemImage: "trash", help: "Move to Trash") {
                model.studio.delete(item)
            }
            Spacer(minLength: 8)
            Text(summary)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// What the object was made with, such as "TRELLIS.2 · Standard · 3 min".
    private var summary: String {
        var parts = [item.record.recipeName]
        if let detail = item.record.request.mesh?.detail { parts.append(detail.title) }
        if let seconds = item.record.durationSeconds {
            parts.append(Duration.seconds(Int(seconds)).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)))
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
