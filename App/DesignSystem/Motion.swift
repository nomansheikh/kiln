import SwiftUI

/// The app's shared animations and transitions. Movement and scale are
/// dropped when Reduce Motion is on, leaving plain fades.
enum Motion {
    /// Layout changes such as the composer moving or rows being inserted.
    static func layout(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(duration: 0.5, bounce: 0.14)
    }

    /// Content arriving, such as a finished image.
    static func arrival(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.25) : .spring(duration: 0.75, bounce: 0.18)
    }

    /// A new item rising into a list from below.
    static func rise(reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .opacity.combined(with: .offset(y: 18))
    }

    /// A row sliding in from the leading edge and collapsing away when removed.
    static func row(reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: -14)),
            removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading))
        )
    }

    /// Content coming into focus: slightly small and blurred, settling to rest.
    static func settle(reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .asymmetric(
            insertion: .modifier(active: SettleEffect(amount: 1), identity: SettleEffect(amount: 0)),
            removal: .opacity
        )
    }
}

/// The unsettled end of `Motion.settle`: `amount` 1 is fully blurred, small and clear.
private struct SettleEffect: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.04 * amount)
            .blur(radius: 14 * amount)
            .opacity(1 - amount)
    }
}
