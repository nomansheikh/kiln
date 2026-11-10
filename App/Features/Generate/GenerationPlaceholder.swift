import SwiftUI

/// Stands in for an image while it is being created: a softly moving wash in
/// the image's shape, with a shimmering status line above it.
struct GenerationPlaceholder: View {
    let phase: GenerationPhase
    let aspectRatio: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            AuroraWash()
                .overlay(alignment: .bottom) { progressBar }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
                .generatedImageFrame(aspectRatio: aspectRatio)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(phase.progressTitle)
        .accessibilityValue(phase.progressDetail ?? "")
    }

    /// A hairline bar along the bottom edge, shown once progress can be measured.
    @ViewBuilder
    private var progressBar: some View {
        if let fraction = phase.progressFraction {
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: max(6, proxy.size.width * fraction))
                    .animation(.smooth(duration: 0.5), value: fraction)
            }
            .frame(height: 3)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

extension View {
    /// Sizes a thread image so its longest side is `GenerateLayout.imageSide`.
    func generatedImageFrame(aspectRatio ratio: CGFloat) -> some View {
        let side = GenerateLayout.imageSide
        return aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: ratio >= 1 ? side : side * ratio, maxHeight: ratio >= 1 ? side / ratio : side)
    }
}

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
