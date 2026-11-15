import SwiftUI

/// A sound drawn as a row of rounded bars. The part already played is in the
/// accent colour; clicking or dragging moves playback there.
///
/// The bars show how loud the sound is, so they hold still while it plays and
/// only the colour moves along. They rise into place once when the sound
/// arrives, and with no sound yet `isWorking` makes the row ripple; both are
/// dropped when Reduce Motion is on.
struct WaveformView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Loudness over time, each from 0 to 1. Empty while it is being read.
    let peaks: [Float]
    /// How much of the sound has played, from 0 to 1.
    let progress: Double
    var isWorking = false
    let onSeek: (Double) -> Void

    /// When the bars started rising into place.
    @State private var revealStart: Date?

    private let barWidth: CGFloat = 3
    private let gap: CGFloat = 2
    private static let revealDuration = 0.7

    var body: some View {
        GeometryReader { proxy in
            Group {
                if !reduceMotion, isWorking || revealStart != nil {
                    TimelineView(.animation) { timeline in
                        bars(at: timeline.date)
                    }
                } else {
                    bars(at: nil)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard proxy.size.width > 0 else { return }
                        onSeek(min(1, max(0, value.location.x / proxy.size.width)))
                    }
            )
        }
        .pointerCursor()
        .onChange(of: peaks.isEmpty) { _, isEmpty in
            guard !isEmpty, !reduceMotion else { return }
            revealStart = Date()
            Task {
                try? await Task.sleep(for: .seconds(Self.revealDuration))
                revealStart = nil
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            onSeek(min(1, max(0, progress + (direction == .increment ? 0.05 : -0.05))))
        }
    }

    /// - Parameter date: The moment being drawn, or nil for a still picture.
    private func bars(at date: Date?) -> some View {
        Canvas { context, size in
            let count = max(1, Int((size.width + gap) / (barWidth + gap)))
            let playhead = Double(count) * progress
            let time = date?.timeIntervalSinceReferenceDate ?? 0
            let revealed = date.flatMap { now in revealStart.map { now.timeIntervalSince($0) / Self.revealDuration } }

            for index in 0..<count {
                var level = Double(self.level(at: index, of: count))
                if isWorking, date != nil {
                    // Two waves of different lengths, so the motion does not look mechanical.
                    let x = Double(index)
                    level = 0.22 + 0.2 * sin(x * 0.35 - time * 4) + 0.12 * sin(x * 0.11 + time * 2.3)
                }
                if let revealed {
                    // Bars rise from left to right, each easing out as it settles.
                    let local = min(1, max(0, (revealed - 0.55 * Double(index) / Double(count)) / 0.45))
                    level *= 1 - pow(1 - local, 3)
                }

                // Even silence keeps a dot, so the row never has holes.
                let height = max(barWidth, CGFloat(level) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + gap), y: (size.height - height) / 2, width: barWidth, height: height
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                // The bar under the playhead fills by the share of it that has played.
                let played = min(1, max(0, playhead - Double(index)))
                context.fill(path, with: .color(.primary.opacity(isWorking ? 0.14 : 0.2)))
                if played > 0 {
                    context.fill(path, with: .color(Theme.accent.opacity(played)))
                }
            }
        }
    }

    /// The loudest peak among those that fall on one bar.
    private func level(at index: Int, of count: Int) -> Float {
        guard !peaks.isEmpty else { return 0 }
        let start = index * peaks.count / count
        let end = max(start + 1, (index + 1) * peaks.count / count)
        return peaks[start..<min(end, peaks.count)].max() ?? 0
    }
}
