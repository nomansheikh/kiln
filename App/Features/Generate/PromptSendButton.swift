import SwiftUI

/// The round send button: an arrow, or a stop square while generating.
struct PromptSendButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isBusy ? "stop.fill" : "arrow.up")
                .font(.system(size: isBusy ? 11 : 14, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(Theme.window)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(isEnabled ? 1 : 0.25), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
        .help(isBusy ? "Stop (\u{2318}.)" : "Generate (\u{21A9})")
        .accessibilityLabel(isBusy ? "Stop" : "Generate")
    }
}
