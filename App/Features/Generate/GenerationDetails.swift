import KilnCore
import SwiftUI

/// The settings an output was made with, shown from its Details button.
struct GenerationDetails: View {
    let record: GenerationRecord

    var body: some View {
        let image = record.request.image

        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            row("Model", record.recipeName)
            if let image {
                row("Size", "\(image.width) × \(image.height)")
                row("Steps", "\(image.steps)")
                row("CFG", image.cfg.formatted(.number.precision(.fractionLength(0...2))))
                row("Sampler", image.sampler)
                row("Seed", String(image.seed))
            }
            if let duration = record.durationSeconds {
                row("Time", Duration.seconds(duration).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
            }
            if let negative = image?.negativePrompt, !negative.isEmpty {
                row("Negative", negative)
            }
        }
        .font(.callout)
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .monospacedDigit()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
