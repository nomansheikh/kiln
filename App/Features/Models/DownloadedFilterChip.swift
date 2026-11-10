import SwiftUI

/// Toggle chip in the Models header that limits the list to models already on this Mac.
struct DownloadedFilterChip: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "arrow.down.circle")
                    .imageScale(.small)
                Text("Downloaded")
            }
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isOn ? Theme.accent : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isOn ? Theme.accent.opacity(0.14) : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Theme.accent.opacity(0.5) : Theme.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show only models that are on this Mac")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
