import SwiftUI

/// A small borderless icon button for the actions under a message.
struct MessageActionButton: View {
    let systemImage: String
    let help: String
    /// Shows a checkmark for a moment after the action, for actions with no other visible result.
    var confirms = false
    /// Bounces the symbol when clicked.
    var bounces = false
    let action: () -> Void

    @State private var confirmed = false
    @State private var clicks = 0

    var body: some View {
        Button {
            action()
            clicks += 1
            guard confirms else { return }
            confirmed = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                confirmed = false
            }
        } label: {
            MessageActionIcon(systemImage: confirmed ? "checkmark" : systemImage)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounces ? clicks : 0)
        }
        .buttonStyle(PressableButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The face of a message action: a secondary symbol with a hover highlight.
struct MessageActionIcon: View {
    @Environment(\.isEnabled) private var isEnabled
    let systemImage: String
    @State private var hovering = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 28)
            .background(Color.primary.opacity(hovering && isEnabled ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
    }
}
