import AppKit
import KilnCore
import SwiftUI

struct GalleryView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: UUID?
    @State private var pendingDelete: GalleryItem?
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)]

    private var selectedItem: GalleryItem? {
        model.galleryItems.first { $0.id == selectedID }
    }

    private var subtitle: String {
        let count = model.galleryItems.count
        switch count {
        case 0: return "Everything you generate is kept here"
        case 1: return "1 image"
        default: return "\(count) images"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Gallery", subtitle: subtitle) {
                Button {
                    model.reloadGallery()
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
            Divider()

            HStack(spacing: 0) {
                Group {
                    if model.galleryItems.isEmpty {
                        emptyState
                    } else {
                        grid
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let item = selectedItem {
                    GalleryDetailPanel(
                        item: item,
                        onClose: { selectedID = nil },
                        onDelete: { pendingDelete = item }
                    )
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("No Images Yet")
                .font(.title3.weight(.semibold))
            Text("Images you generate are saved here with the settings that made them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button {
                model.selection = .generate
            } label: {
                Label("Generate an Image", systemImage: "wand.and.stars")
            }
            .buttonStyle(AccentButtonStyle())
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.galleryItems) { item in
                    GalleryCell(
                        item: item,
                        isSelected: item.id == selectedID,
                        onReuse: { model.reuseSettings(of: item) },
                        onCopy: { model.copyToPasteboard(item) }
                    )
                    .onTapGesture { selectedID = item.id }
                    // Simultaneous, so a single click selects without waiting for a second one.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { NSWorkspace.shared.open(item.url) })
                    .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                    .contextMenu { actions(for: item) }
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

    /// The context menu of each thumbnail.
    @ViewBuilder
    private func actions(for item: GalleryItem) -> some View {
        Button {
            model.reuseSettings(of: item)
        } label: {
            Label("Reuse Settings", systemImage: "arrow.uturn.backward")
        }
        Button {
            model.copyToPasteboard(item)
        } label: {
            Label("Copy Image", systemImage: "doc.on.doc")
        }
        Button {
            copyText(item.record.request.prompt)
        } label: {
            Label("Copy Prompt", systemImage: "text.quote")
        }
        Button {
            model.revealInFinder(item)
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
        ShareLink(item: item.url)
        Divider()
        Button(role: .destructive) {
            pendingDelete = item
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

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

@MainActor
private func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - Cell

private struct GalleryCell: View {
    let item: GalleryItem
    let isSelected: Bool
    let onReuse: () -> Void
    let onCopy: () -> Void

    @State private var hovering = false

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    private var firstPromptLine: String {
        let prompt = item.record.request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { Thumbnail(url: item.url) }
            .overlay(alignment: .bottom) {
                if hovering {
                    scrim.transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isSelected ? Theme.accent : Theme.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if hovering {
                    HStack(spacing: 6) {
                        quickAction("arrow.uturn.backward", help: "Reuse Settings", action: onReuse)
                        quickAction("doc.on.doc", help: "Copy Image", action: onCopy)
                    }
                    .padding(8)
                    .transition(.opacity)
                }
            }
            .contentShape(shape)
            .shadow(color: .black.opacity(hovering ? 0.10 : 0), radius: 8, y: 3)
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
            .accessibilityLabel(item.record.request.prompt)
            .accessibilityAddTraits(isSelected ? [.isImage, .isSelected] : .isImage)
    }

    /// Always dark with white text: it sits on the image, not on the panel.
    private var scrim: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            .frame(height: 72)
            .overlay(alignment: .bottomLeading) {
                Text(firstPromptLine)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
            }
            .allowsHitTesting(false)
    }

    private func quickAction(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.4), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Detail panel

private struct GalleryDetailPanel: View {
    @Environment(AppModel.self) private var model
    let item: GalleryItem
    let onClose: () -> Void
    let onDelete: () -> Void

    private var request: GenerationRequest { item.record.request }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Details")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Theme.card, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    preview

                    textBlock("Prompt", text: request.prompt, copyHelp: "Copy Prompt")
                    if !request.negativePrompt.isEmpty {
                        textBlock("Negative Prompt", text: request.negativePrompt, copyHelp: "Copy Negative Prompt")
                    }

                    settings
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            actionBar
        }
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Color.clear
            .aspectRatio(CGFloat(max(request.width, 1)) / CGFloat(max(request.height, 1)), contentMode: .fit)
            .overlay { Thumbnail(url: item.url, maxPixelSize: 800) }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.hairline) }
            .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
            .help("Double-click to open")
    }

    private func textBlock(_ title: String, text: String, copyHelp: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyText(text)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(copyHelp)
                .accessibilityLabel(copyHelp)
            }
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 12, radius: 10)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Pill(text: "\(request.width) × \(request.height)", systemImage: "aspectratio")
                Pill(text: "\(request.steps) steps")
                Pill(text: "CFG \(request.cfg.formatted())")
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
                detail("Model", item.record.recipeName)
                detail("Sampler", request.sampler)
                detail("Seed", String(request.seed), monospaced: true)
                detail("Created", item.record.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let seconds = item.record.durationSeconds {
                    detail("Duration", "\(seconds.formatted(.number.precision(.fractionLength(1)))) s")
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 12, radius: 10)
    }

    private func detail(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            Button {
                model.reuseSettings(of: item)
            } label: {
                Label("Reuse Settings", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccentButtonStyle())

            HStack(spacing: 8) {
                Button {
                    model.copyToPasteboard(item)
                } label: {
                    Label("Copy Image", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    model.revealInFinder(item)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(SoftButtonStyle())
            .lineLimit(1)

            HStack(spacing: 8) {
                ShareLink(item: item.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle())

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}
