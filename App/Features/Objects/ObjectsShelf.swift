import KilnCore
import SwiftUI

/// Past objects as a row of small pictures. Clicking one puts it on the stage.
struct ObjectsShelf: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let studio = model.studio
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if studio.isGenerating || studio.proposal != nil {
                    ObjectWorkTile(
                        picture: studio.workingPicture ?? studio.proposal?.url, fraction: studio.activity.fraction,
                        isWorking: studio.isGenerating, selected: showsWork
                    ) {
                        studio.watchWork()
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                ForEach(model.objects.items) { item in
                    ObjectTile(item: item, selected: !showsWork && item.id == studio.current?.id, isNew: item.id == studio.unseenID) {
                        studio.show(item)
                    }
                    .contextMenu {
                        Button("Use These Settings Again") { studio.reuse(item) }
                        Button("Show in Finder") { model.objects.revealInFinder(item) }
                        Divider()
                        Button("Move to Trash", role: .destructive) { studio.delete(item) }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
        .animation(.snappy(duration: 0.25), value: studio.isGenerating)
    }

    /// True when the stage shows what is being made and not an earlier object.
    private var showsWork: Bool {
        let studio = model.studio
        return (studio.isGenerating || studio.proposal != nil) && (studio.watchesWork || studio.current == nil)
    }
}

/// One object on the shelf: its picture, rendered once and kept beside its file.
struct ObjectTile: View {
    let item: MeshItem
    let selected: Bool
    /// Marks an object that finished while another was being looked at.
    var isNew = false
    let action: () -> Void

    @State private var picture: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            ZStack {
                StageBackdrop()
                if let picture {
                    Image(nsImage: picture)
                        .resizable()
                        .scaledToFit()
                        .transition(.opacity)
                } else {
                    Image(systemName: "cube")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if isNew {
                    Circle().fill(Theme.accent).frame(width: 9, height: 9).padding(6)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.95))
        .pointerCursor()
        .hint(isNew ? "New: just finished" : "Made \(item.record.createdAt.formatted(date: .abbreviated, time: .shortened))", alignment: .topLeading)
        .task(id: item.id) {
            let item = item
            let file = await Task.detached(priority: .utility) { MeshThumbnail.file(of: item) }.value
            picture = file.flatMap(NSImage.init(contentsOf:))
        }
    }
}
