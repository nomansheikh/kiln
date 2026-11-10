import SwiftUI

/// The Settings screen: a column of cards for the account, hardware, storage
/// and app information.
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Settings", subtitle: "Accounts, hardware and storage")
            Divider()
            StableScrollView {
                VStack(spacing: 18) {
                    HuggingFaceCard()
                    HardwareCard()
                    StorageCard()
                    AboutCard()
                }
                .frame(maxWidth: 700)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
