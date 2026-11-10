import KilnCore
import SwiftUI

/// The progress and controls of a recipe download, for whichever state the transfer is in.
struct RecipeTransferView: View {
    let status: DownloadStatus
    /// Speed and time left, once they can be estimated.
    var speed: DownloadSpeed?
    /// Starts, resumes or retries the download.
    let download: () -> Void
    let pause: () -> Void
    let cancel: () -> Void
    /// Clears a failed download.
    let dismiss: () -> Void

    var body: some View {
        switch status.state {
        case .queued:
            RecipeTransferRow(value: 0, caption: "Waiting…") {
                cancelButton
            }
        case .downloading, .paused:
            // One row for both states, so the button's symbol morphs between pause and play.
            let isPaused = status.state == .paused
            RecipeTransferRow(
                value: status.fraction,
                caption: isPaused ? "Paused · " + status.transferCaption : downloadingCaption
            ) {
                ModelsIconButton(
                    systemImage: isPaused ? "play.fill" : "pause.fill",
                    help: isPaused ? "Resume download" : "Pause download",
                    action: isPaused ? download : pause
                )
                cancelButton
            }
        case .verifying:
            RecipeTransferRow(value: nil, caption: "Verifying…") { EmptyView() }
        case .failed(let message):
            RecipeTransferFailure(message: message, retry: download, dismiss: dismiss)
        case .completed:
            EmptyView()
        }
    }

    private var downloadingCaption: String {
        [status.transferCaption, speed?.summary].compactMap { $0 }.joined(separator: " · ")
    }

    private var cancelButton: some View {
        ModelsIconButton(systemImage: "xmark", help: "Cancel download", action: cancel)
    }
}
