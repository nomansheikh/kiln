import SwiftUI

/// Quiet neutral tile with the owner's initial, in place of a colourful avatar.
struct ModelsMonogram: View {
    let name: String
    var size: CGFloat = 36

    private var initial: String {
        String(name.first { $0.isLetter || $0.isNumber } ?? "?").uppercased()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Theme.hairline))
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            )
            .accessibilityHidden(true)
    }
}
