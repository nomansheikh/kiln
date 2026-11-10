import SwiftUI

/// A titled card: plain symbol, title and optional description, then rows.
struct SettingsCard<Accessory: View, Content: View>: View {
    let title: String
    let symbol: String
    var description: String?
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    if let description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                accessory
            }
            SettingsRowDivider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
    }
}

extension SettingsCard where Accessory == EmptyView {
    /// A card with nothing on the trailing edge of its title.
    init(title: String, symbol: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, description: description, accessory: { EmptyView() }, content: content)
    }
}
