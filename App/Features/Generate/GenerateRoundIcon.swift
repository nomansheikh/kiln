import SwiftUI

/// A 28 pt round grey button face holding one symbol.
struct GenerateRoundIcon: View {
    let systemImage: String
    var active = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(active ? 0.1 : 0.06), in: Circle())
            .contentShape(Circle())
    }
}
