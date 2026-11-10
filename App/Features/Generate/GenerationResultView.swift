import AppKit
import KilnCore
import SwiftUI

/// The canvas after a generation: the image, its prompt, actions and settings.
struct GenerationResultView: View {
    @Environment(AppModel.self) private var model
    let item: GalleryItem
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 14) {
            picture
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(verbatim: request.prompt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: 620)

            actions
            metadata
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .task(id: item.id) {
            image = NSImage(contentsOf: item.url)
        }
    }

    private var request: GenerationRequest { item.record.request }

    // MARK: - Sections

    @ViewBuilder
    private var picture: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.10), radius: 16, y: 4)
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                .transition(.opacity)
        } else {
            Color.clear
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { model.gallery.copyToPasteboard(item) } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button { GenerationResultExporter.saveCopy(of: item) } label: {
                Label("Save As…", systemImage: "square.and.arrow.down")
            }
            ShareLink(item: item.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button { model.gallery.revealInFinder(item) } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
        .buttonStyle(SoftButtonStyle())
        .lineLimit(1)
    }

    private var metadata: some View {
        GenerateFlowLayout(spacing: 6) {
            Pill(text: item.record.recipeName, systemImage: "cube")
            Pill(text: "\(request.width) × \(request.height)", systemImage: "aspectratio")
            Pill(text: "\(request.steps) steps", systemImage: "square.stack.3d.up")
            Pill(text: "Seed \(request.seed)", systemImage: "dice")
            if let seconds = item.record.durationSeconds {
                Pill(text: "\(seconds.formatted(.number.precision(.fractionLength(1)))) s", systemImage: "timer")
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .textSelection(.enabled)
    }
}
