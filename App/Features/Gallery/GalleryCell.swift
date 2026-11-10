import KilnCore
import SwiftUI

/// One square thumbnail in the gallery grid. Hovering reveals the prompt and
/// two quick actions.
struct GalleryCell: View {
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
