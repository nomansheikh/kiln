import KilnCore
import SwiftUI

/// Stands in for an image while it is being created. Once the engine sends
/// step previews the picture is shown emerging, soft at first and sharpening
/// as the steps complete; until then a slow colour wash fills its shape.
struct GenerationPlaceholder: View {
    let phase: GenerationPhase
    let aspectRatio: CGFloat
    /// The engine's rough picture of the image so far, if it has sent one.
    let preview: GeneratedImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ShimmeringText(text: phase.progressTitle)
                if let detail = phase.progressDetail {
                    Text(detail)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.callout.weight(.medium))
            .animation(.snappy, value: phase)

            canvas
                .overlay(alignment: .bottom) { progressBar }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.hairline))
                .generatedImageFrame(aspectRatio: aspectRatio)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(phase.progressTitle)
        .accessibilityValue(phase.progressDetail ?? "")
    }

    // MARK: - Layers

    private var canvas: some View {
        // The preview sits in an overlay so its own size can never stretch the placeholder.
        AuroraWash()
            .overlay { previewLayer }
            .animation(.smooth(duration: 0.7), value: preview)
    }

    @ViewBuilder
    private var previewLayer: some View {
        let remaining = 1 - (phase.progressFraction ?? 0)
        if let preview, let image = try? ImageCodec.cgImage(from: preview) {
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    // Early previews are mostly noise; the blur lifts as the image settles.
                    .blur(radius: 2 + 14 * remaining)
                    .scaleEffect(1.06)
                AuroraWash()
                    .opacity(0.35 * remaining)
                    .blendMode(.plusLighter)
            }
            .id(preview)
            .transition(.opacity)
        }
    }

    /// A hairline bar along the bottom edge, shown once progress can be measured.
    @ViewBuilder
    private var progressBar: some View {
        if let fraction = phase.progressFraction {
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: max(6, proxy.size.width * fraction))
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .animation(.smooth(duration: 0.5), value: fraction)
            }
            .frame(height: 3)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

extension View {
    /// Sizes a thread image so its longest side is `GenerateLayout.imageSide`.
    func generatedImageFrame(aspectRatio ratio: CGFloat) -> some View {
        let side = GenerateLayout.imageSide
        return aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: ratio >= 1 ? side : side * ratio, maxHeight: ratio >= 1 ? side / ratio : side)
    }
}
