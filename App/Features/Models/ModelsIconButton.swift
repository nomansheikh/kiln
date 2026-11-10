import SwiftUI

/// Compact icon-only secondary button.
struct ModelsIconButton: View {
    let systemImage: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 14, height: 17)
        }
        .buttonStyle(SoftButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}
