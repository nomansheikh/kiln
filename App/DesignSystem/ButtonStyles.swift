import SwiftUI

/// Filled accent button, the app's primary action style.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .pressScale(configuration.isPressed)
    }
}

/// Quiet rounded button for secondary actions.
struct SoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Theme.cardHover : Theme.card, in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .pressScale(configuration.isPressed)
    }
}

/// For buttons that draw their own face: no chrome, just a small dip when pressed.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pressScale(configuration.isPressed, to: scale)
    }
}

extension View {
    /// Shrinks slightly while pressed and springs back on release.
    func pressScale(_ isPressed: Bool, to scale: CGFloat = 0.96) -> some View {
        scaleEffect(isPressed ? scale : 1)
            .animation(.snappy(duration: 0.18), value: isPressed)
    }
}
