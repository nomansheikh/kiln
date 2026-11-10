import AppKit
import KilnCore
import SwiftUI

/// A finished image in the thread with its row of quiet actions.
struct GeneratedImageMessage: View {
    @Environment(AppModel.self) private var model
    let item: GalleryItem
    let aspectRatio: CGFloat
    let regenerate: () -> Void
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumbnail(url: item.url, maxPixelSize: 1400)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
                .generatedImageFrame(aspectRatio: aspectRatio)
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
                .help("Double-click to open. Drag to copy the file.")
                .accessibilityLabel("Generated image: \(item.record.request.prompt)")

            HStack(spacing: 2) {
                MessageActionButton(systemImage: "doc.on.doc", help: "Copy image", confirms: true) {
                    model.gallery.copyToPasteboard(item)
                }
                MessageActionButton(systemImage: "arrow.down.to.line", help: "Save As…") {
                    GenerationResultExporter.saveCopy(of: item)
                }
                ShareLink(item: item.url) {
                    MessageActionIcon(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PressableButtonStyle())
                .help("Share")
                MessageActionButton(systemImage: "folder", help: "Show in Finder") {
                    model.gallery.revealInFinder(item)
                }
                MessageActionButton(systemImage: "pencil", help: "Edit this image") {
                    try? model.generation.attach(item.url)
                }
                MessageActionButton(systemImage: "arrow.clockwise", help: "Generate again", bounces: true) {
                    regenerate()
                }
                .disabled(model.generation.phase.isBusy)
                MessageActionButton(systemImage: "info.circle", help: "Details") {
                    showsDetails.toggle()
                }
                .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                    GenerationDetails(record: item.record)
                }
            }
        }
    }
}
