import SwiftUI

/// A field of short strokes that turn with a slow current, like grass in wind,
/// brightening where waves of colour pass through.
struct AuroraWash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.self) private var environment

    private static let violet = Color(red: 0.72, green: 0.55, blue: 0.98)
    /// Distance between stroke centres, in points.
    private static let spacing: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let from = Theme.accent.resolve(in: environment)
            let to = Self.violet.resolve(in: environment)
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.05)))
                let columns = max(2, Int(size.width / Self.spacing))
                let rows = max(2, Int(size.height / Self.spacing))
                for row in 0..<rows {
                    for column in 0..<columns {
                        let x = Double(column) / Double(columns - 1)
                        let y = Double(row) / Double(rows - 1)
                        let level = Self.level(x, y, time)
                        let angle = Self.angle(x, y, time)
                        let reach = 2 + 3 * level
                        let centre = CGPoint(
                            x: (Double(column) + 0.5) * size.width / Double(columns),
                            y: (Double(row) + 0.5) * size.height / Double(rows)
                        )
                        var stroke = Path()
                        stroke.move(to: CGPoint(x: centre.x - cos(angle) * reach, y: centre.y - sin(angle) * reach))
                        stroke.addLine(to: CGPoint(x: centre.x + cos(angle) * reach, y: centre.y + sin(angle) * reach))
                        let color = Self.mix(from, to, Self.blend(x, y, time)).opacity(0.08 + 0.85 * level)
                        context.stroke(stroke, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    }
                }
            }
        }
    }

    /// How lit the stroke at a point is, from 0 to 1: a few waves crossing at different
    /// angles and speeds, so bright patches form, travel and dissolve without repeating.
    private static func level(_ x: Double, _ y: Double, _ time: Double) -> Double {
        let ripple = hypot(x - 0.5 - 0.3 * sin(time * 0.21), y - 0.5 - 0.3 * cos(time * 0.17))
        let straight = sin(x * 4.2 + time * 0.55) + sin(y * 3.4 - time * 0.42)
        let crossing = sin((x + y) * 2.6 + time * 0.31) + sin(ripple * 7 - time * 0.6)
        let value = ((straight + crossing) / 4 + 1) / 2
        // Steepened so the quiet areas fall nearly dark and the lit ones stand out.
        return value * value * (3 - 2 * value)
    }

    /// The direction of the current at a point, in radians. Neighbours differ only
    /// slightly, which is what makes the strokes read as one flowing surface.
    private static func angle(_ x: Double, _ y: Double, _ time: Double) -> Double {
        let swirl = sin(x * 3 + time * 0.3) + cos(y * 3 - time * 0.25)
        return (swirl + sin((x - y) * 2 + time * 0.2)) * 1.2
    }

    /// How far a point sits between the two colours, from 0 to 1, along a slow diagonal drift.
    private static func blend(_ x: Double, _ y: Double, _ time: Double) -> Double {
        0.5 + 0.5 * sin(x * 2.4 - y * 1.6 + time * 0.25)
    }

    private static func mix(_ from: Color.Resolved, _ to: Color.Resolved, _ amount: Double) -> Color {
        let amount = Float(amount)
        return Color(
            .sRGBLinear,
            red: Double(from.linearRed + (to.linearRed - from.linearRed) * amount),
            green: Double(from.linearGreen + (to.linearGreen - from.linearGreen) * amount),
            blue: Double(from.linearBlue + (to.linearBlue - from.linearBlue) * amount)
        )
    }
}
