import SwiftUI

/// A small round grey button holding one symbol, for compact controls.
struct RoundIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Theme.card, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
        // Mouse-driven; a focus ring on a 24 pt control only adds noise.
        .focusable(false)
        .help(help)
        .accessibilityLabel(help)
    }
}
