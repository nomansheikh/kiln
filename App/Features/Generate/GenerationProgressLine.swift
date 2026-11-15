import SwiftUI

/// Stands in for a reply that is not a picture while it is being made: what
/// the model is doing, and how far along it is when that can be measured.
struct GenerationProgressLine: View {
    let phase: GenerationPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if let fraction = phase.progressFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 220)
                    .animation(.smooth(duration: 0.5), value: fraction)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(phase.progressTitle)
        .accessibilityValue(phase.progressDetail ?? "")
    }
}
