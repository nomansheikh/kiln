import SwiftUI

/// The composer's border as a sign of what it is doing: a steady accent line
/// while it has the keyboard, and a glow travelling around it while a model
/// is working. With Reduce Motion the glow holds still. A click outside the
/// composer takes the keyboard away from it.
struct ComposerGlow: ViewModifier {
    let isWorking: Bool
    let isFocused: Bool
    var cornerRadius: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Names this composer's frame to `FocusDismissal`.
    @State private var region = UUID()

    /// How long the glow takes to go round once.
    private static let period: TimeInterval = 3.2

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            // A click anywhere outside this frame gives the keyboard up.
            .background {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .global)
                    Color.clear
                        .onAppear { FocusDismissal.shared.setRegion(frame, for: region) }
                        .onChange(of: frame) { _, frame in FocusDismissal.shared.setRegion(frame, for: region) }
                        .onDisappear { FocusDismissal.shared.setRegion(nil, for: region) }
                }
            }
            .overlay {
                ZStack {
                    if isWorking {
                        working(shape)
                            .transition(.opacity)
                    } else if isFocused {
                        shape.strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1)
                            .transition(.opacity)
                    }
                }
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.3), value: isWorking)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
            }
    }

    @ViewBuilder
    private func working(_ shape: RoundedRectangle) -> some View {
        if reduceMotion {
            ring(shape, turn: 0.6)
        } else {
            TimelineView(.animation) { timeline in
                ring(shape, turn: timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.period) / Self.period)
            }
        }
    }

    /// A bright arc on a faint full border, with a soft halo of the same arc behind it.
    private func ring(_ shape: RoundedRectangle, turn: Double) -> some View {
        let arc = AngularGradient(
            stops: [
                .init(color: Theme.accent.opacity(0), location: 0),
                .init(color: Theme.accent.opacity(0), location: 0.45),
                .init(color: Theme.accent, location: 0.7),
                .init(color: Color.white.opacity(0.55), location: 0.8),
                .init(color: Theme.accent, location: 0.9),
                .init(color: Theme.accent.opacity(0), location: 1),
            ],
            center: .center,
            angle: .degrees(turn * 360)
        )
        return ZStack {
            shape.strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1)
            shape.stroke(arc, lineWidth: 5)
                .blur(radius: 9)
                .opacity(0.6)
            shape.strokeBorder(arc, lineWidth: 1.5)
        }
    }
}

extension View {
    /// Marks a composer as focused or working. See `ComposerGlow`.
    func composerGlow(isWorking: Bool, isFocused: Bool) -> some View {
        modifier(ComposerGlow(isWorking: isWorking, isFocused: isFocused))
    }
}
