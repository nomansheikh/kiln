import SwiftUI

/// The app's name and version, the check for new versions, a link to the source and licensing notes.
struct AboutCard: View {
    @Environment(AppModel.self) private var model

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Kiln"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development build"
    }

    private static let repository = URL(string: "https://github.com/nomansheikh/kiln")!

    var body: some View {
        SettingsCard(title: "About", symbol: "info.circle") {
            SettingsRow(appName, description: Text("Runs image and speech models you download, on this Mac.")) {
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
                description: Text(
                    "Kiln is open source under the MIT license. It runs models with stable-diffusion.cpp, whisper.cpp and audio.cpp."
                )
            ) {
                Link("View on GitHub", destination: Self.repository)
                    .buttonStyle(SoftButtonStyle())
                    .pointerCursor()
            }
            SettingsRowDivider()
            SettingsRow(
                "Model licenses",
                description: Text("Each model's license is set by its authors. Check the model's page before using what it makes.")
            ) {
                EmptyView()
            }
        }
    }
}
