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
                MessageActionButton(systemImage: "doc.on.doc", help: "Copy image") {
                    model.gallery.copyToPasteboard(item)
                }
                MessageActionButton(systemImage: "arrow.down.to.line", help: "Save As…") {
                    GenerationResultExporter.saveCopy(of: item)
                }
                ShareLink(item: item.url) {
                    MessageActionIcon(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Share")
                MessageActionButton(systemImage: "folder", help: "Show in Finder") {
                    model.gallery.revealInFinder(item)
                }
                MessageActionButton(systemImage: "arrow.clockwise", help: "Generate again") {
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

/// A small borderless icon button that highlights on hover, for message actions.
struct MessageActionButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MessageActionIcon(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The face of a message action: a secondary symbol with a hover highlight.
struct MessageActionIcon: View {
    @Environment(\.isEnabled) private var isEnabled
    let systemImage: String
    @State private var hovering = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 28)
            .background(Color.primary.opacity(hovering && isEnabled ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
    }
}
