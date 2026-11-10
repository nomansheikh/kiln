import SwiftUI

/// A faint band of light sweeping across the progress placeholder.
struct GenerateShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Theme.card
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let sweep = time.truncatingRemainder(dividingBy: 2.4) / 2.4
                GeometryReader { geometry in
                    let width = geometry.size.width
                    ZStack(alignment: .leading) {
                        Theme.card.opacity(0.6)
                        LinearGradient(
                            colors: [.clear, Theme.accent.opacity(0.10), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.6)
                        .offset(x: -width * 0.6 + sweep * width * 1.6)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
