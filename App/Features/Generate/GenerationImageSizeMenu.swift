import SwiftUI

/// The composer's round button that picks the output size from the presets.
struct GenerationImageSizeMenu: View {
    @Binding var draft: GenerationDraft

    var body: some View {
        let current = GenerationImageSize(width: draft.width, height: draft.height)
        Menu {
            ForEach(sizes(including: current), id: \.self) { size in
                Button {
                    draft.width = size.width
                    draft.height = size.height
                } label: {
                    if size == current {
                        Label(size.title, systemImage: "checkmark")
                    } else {
                        Text(verbatim: size.title)
                    }
                }
            }
        } label: {
            GenerateRoundIcon(systemImage: "aspectratio")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Image size: \(current.title)")
        .accessibilityLabel("Image size")
        .accessibilityValue(current.title)
    }

    /// The presets, plus the current size when a recipe set one that is not a preset.
    private func sizes(including current: GenerationImageSize) -> [GenerationImageSize] {
        let presets = GenerationImageSize.presets
        return presets.contains(current) ? presets : presets + [current]
    }
}
