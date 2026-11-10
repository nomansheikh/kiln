import SwiftUI

/// Secondary text with a highlight sweeping across it.
struct ShimmeringText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .overlay {
                if !reduceMotion {
                    TimelineView(.animation) { timeline in
                        let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                        LinearGradient(
                            colors: [.clear, Color.primary.opacity(0.9), .clear],
                            startPoint: UnitPoint(x: cycle * 2 - 0.6, y: 0.5),
                            endPoint: UnitPoint(x: cycle * 2 - 0.1, y: 0.5)
                        )
                        .mask(Text(text))
                    }
                }
            }
    }
}
