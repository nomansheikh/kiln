import SwiftUI

/// The app's name and version, the check for new versions, and licensing notes.
struct AboutCard: View {
    @Environment(AppModel.self) private var model

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
                "Check for new versions",
                description: Text("Once a day, Kiln asks GitHub for its latest release; nothing about you is sent and nothing is downloaded.")
            ) {
                Toggle("Check for new versions", isOn: Binding(
                    get: { model.updates.isEnabled },
                    set: { model.updates.isEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
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
