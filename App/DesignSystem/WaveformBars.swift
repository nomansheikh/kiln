import SwiftUI

/// A few bars moving like a sound level, for something that is listening or speaking.
/// Still when Reduce Motion is on.
struct WaveformBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var count = 5
    var color = Theme.accent

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: height(of: index, at: time))
                }
            }
            .frame(height: 16)
        }
        .accessibilityHidden(true)
    }

    /// Each bar swings at its own pace, so the row never repeats visibly.
    private func height(of index: Int, at time: TimeInterval) -> CGFloat {
        let rest: [CGFloat] = [7, 12, 16, 10, 6]
        guard !reduceMotion else { return rest[index % rest.count] }
        let swing = sin(time * (4.2 + Double(index) * 0.9) + Double(index) * 1.7)
        return 4 + 12 * CGFloat((swing + 1) / 2)
    }
}
