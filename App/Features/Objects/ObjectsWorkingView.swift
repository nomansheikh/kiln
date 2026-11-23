import KilnCore
import SwiftUI

/// The stage while an object is being made: the picture it comes from, lifted
/// off the backdrop, with how far along the model is underneath.
struct ObjectsWorkingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let picture: URL?
    /// What is being drawn, while there is no picture yet.
    var prompt = ""
    let activity: ObjectsStore.Activity
    let startedAt: Date?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack {
            StageBackdrop()
            VStack(spacing: 22) {
                if let picture {
                    Thumbnail(url: picture, maxPixelSize: 640)
                        .frame(width: 210, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.18)))
                        .shadow(color: .black.opacity(0.28), radius: 26, y: 16)
                        // A slow rise and fall, as if the picture were about to lift off the wall.
                        .phaseAnimator(reduceMotion ? [false] : [false, true]) { picture, lifted in
                            picture
                                .offset(y: lifted ? -7 : 7)
                                .scaleEffect(lifted ? 1.02 : 0.99)
                        } animation: { _ in .easeInOut(duration: 3.2) }
                }
                if picture == nil, !prompt.isEmpty {
                    Text("\u{201C}\(prompt)\u{201D}")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 460)
                }
                VStack(spacing: 8) {
                    ShimmeringText(text: title)
                        .font(.system(size: 15, weight: .medium))
                    ProgressView(value: activity.fraction ?? 0)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                        .frame(width: 220)
                        .opacity(activity.fraction == nil ? 0.35 : 1)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(detail(at: context.date))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(24)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hairline))
    }

    private var title: String {
        switch activity {
        case .idle, .starting: "Getting ready"
        case .picturing: "Drawing a picture of it first"
        case .building(let progress): progress.stage == .building ? "Building the 3D object" : "Working"
        }
    }

    /// How far along it is and how long it has taken, such as "43% · 1:14".
    private func detail(at date: Date) -> String {
        var parts: [String] = []
        if let fraction = activity.fraction {
            parts.append(fraction.formatted(.percent.precision(.fractionLength(0))))
        }
        if let startedAt {
            let seconds = max(0, Int(date.timeIntervalSince(startedAt)))
            parts.append("\(seconds / 60):" + String(format: "%02d", seconds % 60))
        }
        return parts.isEmpty ? "This takes a few minutes" : parts.joined(separator: " \u{00B7} ")
    }
}
