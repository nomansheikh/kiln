import SwiftUI

/// Slow, soft colour drifting over a neutral base.
struct AuroraWash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Color.primary.opacity(0.05)
                    blob(Theme.accent, at: time * 0.35, phase: 0, in: size)
                    blob(Color(red: 0.72, green: 0.55, blue: 0.98), at: time * 0.28, phase: 2.1, in: size)
                    blob(Color(red: 0.99, green: 0.62, blue: 0.72), at: time * 0.22, phase: 4.2, in: size)
                }
            }
        }
    }

    private func blob(_ color: Color, at time: Double, phase: Double, in size: CGSize) -> some View {
        // Radial fades give soft edges without a blur pass.
        let diameter = max(size.width, size.height) * 1.1
        return Circle()
            .fill(RadialGradient(colors: [color.opacity(0.5), color.opacity(0)], center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
            .position(
                x: size.width * (0.5 + 0.32 * cos(time + phase)),
                y: size.height * (0.5 + 0.32 * sin(time * 1.3 + phase))
            )
    }
}
