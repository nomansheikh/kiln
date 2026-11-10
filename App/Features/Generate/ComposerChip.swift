import SwiftUI

/// A quiet capsule in the composer showing a setting's symbol and current value.
struct ComposerChip: View {
    let systemImage: String
    let title: String
    var active = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
            Text(verbatim: title)
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.primary.opacity(active ? 0.1 : 0.06), in: Capsule())
        .contentShape(Capsule())
    }
}
