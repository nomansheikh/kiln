import SwiftUI

extension View {
    /// The shared card with a subtle highlight while the pointer is over it.
    func modelsCard(hovering: Bool) -> some View {
        self
            .card(padding: 18)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.025 : 0))
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    /// Inset rounded surface that holds file rows inside a card.
    func modelsInsetSurface() -> some View {
        self
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
    }
}
