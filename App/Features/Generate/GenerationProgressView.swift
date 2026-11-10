import SwiftUI

/// The canvas while an image is generating: a shimmering placeholder in the
/// image's shape with the current stage and progress.
struct GenerationProgressView: View {
    let phase: GenerationPhase
    let prompt: String
    let aspectRatio: CGFloat

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface)
                GenerateShimmer()
                status
                    .padding(24)
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.06), radius: 16, y: 4)
            .frame(maxWidth: 560, maxHeight: 560)

            if !prompt.isEmpty {
                Text(verbatim: prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 560)
            }
        }
        .padding(28)
    }

    private var status: some View {
        VStack(spacing: 10) {
            Text(verbatim: phase.progressTitle)
                .font(.headline)

            if let detail = phase.progressDetail {
                Text(verbatim: detail)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Group {
                if let fraction = phase.progressFraction {
                    ProgressView(value: min(max(fraction, 0), 1))
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .controlSize(.small)
            .tint(Theme.accent)
            .frame(maxWidth: 220)
            .padding(.top, 4)
        }
    }
}
