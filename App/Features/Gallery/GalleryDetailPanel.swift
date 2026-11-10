import AppKit
import KilnCore
import SwiftUI

/// The side panel for the selected image: a preview, its prompts, the settings
/// that made it, and the actions that apply to it.
struct GalleryDetailPanel: View {
    let item: GalleryItem
    let actions: GalleryItemActions
    let onClose: () -> Void

    private var request: GenerationRequest { item.record.request }

    var body: some View {
        VStack(spacing: 0) {
            header
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
            GalleryDetailActionBar(item: item, actions: actions)
        }
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
    }

    // MARK: - Header

    private var header: some View {
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
    }

    // MARK: - Preview

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

    // MARK: - Prompts

    private func textBlock(_ title: String, text: String, copyHelp: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.copyText(text)
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

    // MARK: - Settings

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
}
