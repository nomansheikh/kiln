import SwiftUI

/// The hairline between two rows of a settings card.
struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}
