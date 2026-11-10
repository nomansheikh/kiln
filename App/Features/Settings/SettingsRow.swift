import SwiftUI

/// Title and description on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    let description: Text?
    let control: Control

    init(_ title: String, description: Text? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.medium)
                if let description {
                    description
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
    }
}

extension SettingsRow where Control == Text {
    /// A read-only row showing a value.
    init(_ title: String, description: Text? = nil, value: String) {
        self.init(title, description: description) {
            Text(value).foregroundStyle(.secondary)
        }
    }
}
