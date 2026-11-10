import SwiftUI

/// The app's name, version and licensing notes.
struct AboutCard: View {
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Kiln"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development build"
    }

    var body: some View {
        SettingsCard(title: "About", symbol: "info.circle") {
            SettingsRow(appName, description: Text("Generates images on this Mac with models you download.")) {
                Pill(text: version)
            }
            SettingsRowDivider()
            SettingsRow(
                "Open source",
                description: Text("Kiln is open source under the MIT license and runs models with stable-diffusion.cpp.")
            ) {
                EmptyView()
            }
            SettingsRowDivider()
            SettingsRow(
                "Model licenses",
                description: Text("Each model's license is set by its authors. Check the model's page before using its images.")
            ) {
                EmptyView()
            }
        }
    }
}
