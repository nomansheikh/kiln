import SwiftUI

/// Shown in place of the grid until the first image is generated.
struct GalleryEmptyState: View {
    let onGenerate: () -> Void

    var body: some View {
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
            Button(action: onGenerate) {
                Label("Generate an Image", systemImage: "wand.and.stars")
            }
            .buttonStyle(AccentButtonStyle())
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
