import SwiftUI

/// Small secondary heading above a group of cards. Given a binding, it becomes
/// a button that collapses and expands the group.
struct ModelsSectionTitle: View {
    let text: String
    var count: Int?
    var isExpanded: Binding<Bool>?

    var body: some View {
        if let isExpanded {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                label(chevronExpanded: isExpanded.wrappedValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded.wrappedValue ? "Collapse \(text)" : "Expand \(text)")
            .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
        } else {
            label(chevronExpanded: nil)
        }
    }

    private func label(chevronExpanded: Bool?) -> some View {
        HStack(spacing: 6) {
            if let chevronExpanded {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(chevronExpanded ? 90 : 0))
                    .animation(.snappy(duration: 0.2), value: chevronExpanded)
            }
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
        .padding(.leading, 2)
    }
}
