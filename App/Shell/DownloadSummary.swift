import KilnCore
import SwiftUI

/// The download in progress, always visible at the bottom of the sidebar.
struct DownloadSummary: View {
    @Environment(AppModel.self) private var model
    let recipe: ModelRecipe
    let status: DownloadStatus

    var body: some View {
        Button {
            model.selection = .models
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
                    Text(recipe.name).font(.caption.weight(.semibold)).lineLimit(1)
                }
                ProgressView(value: status.fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                Text(caption).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            .card(padding: 10, radius: 10)
        }
        .buttonStyle(.plain)
    }

    private var caption: String {
        switch status.state {
        case .queued: "Waiting…"
        case .verifying: "Verifying…"
        default: status.fraction.map { "\(Int($0 * 100))% downloaded" } ?? "Downloading…"
        }
    }
}
