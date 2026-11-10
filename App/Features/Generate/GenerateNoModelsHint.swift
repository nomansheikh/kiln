import SwiftUI

/// The line under the composer that points to the Models screen when nothing is installed.
struct GenerateNoModelsHint: View {
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("No models installed yet.")
                .foregroundStyle(.secondary)
            Button("Download a model", action: onDownload)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}
