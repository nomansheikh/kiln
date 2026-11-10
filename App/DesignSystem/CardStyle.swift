import SwiftUI

extension View {
    /// A white rounded card with a hairline border and a very soft shadow.
    func card(padding: CGFloat = 16, radius: CGFloat = Theme.cardRadius) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}
