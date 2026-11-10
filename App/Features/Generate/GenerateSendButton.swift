import SwiftUI

/// The composer's round primary button: generate when idle, stop while busy.
struct GenerateSendButton: View {
    let isBusy: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: isBusy ? "stop.fill" : "arrow.up")
                .font(.system(size: isBusy ? 10 : 13, weight: .bold))
                .foregroundStyle(isBusy ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(.white))
                .frame(width: 30, height: 30)
                .background(isBusy ? AnyShapeStyle(Color.primary.opacity(0.85)) : AnyShapeStyle(Theme.accent), in: Circle())
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .help(isBusy ? "Stop (⌘.)" : "Generate (⌘↩)")
        .accessibilityLabel(isBusy ? "Stop" : "Generate")
    }
}
