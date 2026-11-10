import SwiftUI

/// A download arrow inside a ring that fills as the download progresses.
struct DownloadProgressRing: View {
    /// Completed share, or nil when it is not known.
    let fraction: Double?
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.14), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.4), value: fraction)
            Image(systemName: "arrow.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isActive ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .symbolEffect(.pulse, isActive: isActive && fraction == nil)
        }
        .accessibilityElement()
        .accessibilityLabel("Download progress")
        .accessibilityValue(fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
    }
}
