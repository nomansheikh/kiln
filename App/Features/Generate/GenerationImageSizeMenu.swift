import SwiftUI

/// The composer's chip that shows the output size and picks another from the presets.
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
            ComposerChip(systemImage: "aspectratio", title: current.title)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .help("Image size")
        .accessibilityLabel("Image size")
        .accessibilityValue(current.title)
    }

    /// The presets, plus the current size when a recipe set one that is not a preset.
    private func sizes(including current: GenerationImageSize) -> [GenerationImageSize] {
        let presets = GenerationImageSize.presets
        return presets.contains(current) ? presets : presets + [current]
    }
}
