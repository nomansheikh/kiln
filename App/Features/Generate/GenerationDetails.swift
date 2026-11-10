import KilnCore
import SwiftUI

/// The settings an image was made with, shown from its Details button.
struct GenerationDetails: View {
    let record: GenerationRecord

    var body: some View {
        let request = record.request

        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            row("Model", record.recipeName)
            row("Size", "\(request.width) × \(request.height)")
            row("Steps", "\(request.steps)")
            row("CFG", request.cfg.formatted(.number.precision(.fractionLength(0...2))))
            row("Sampler", request.sampler)
            row("Seed", String(request.seed))
            if let duration = record.durationSeconds {
                row("Time", Duration.seconds(duration).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
            }
            if !request.negativePrompt.isEmpty {
                row("Negative", request.negativePrompt)
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
