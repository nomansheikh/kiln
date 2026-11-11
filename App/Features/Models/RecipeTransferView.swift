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
        case .queued, .downloading, .paused:
            // One row for all three, so the button's symbol morphs between pause and play.
            // Resuming passes through queued, which must keep the same button for that to happen.
            let isPaused = status.state == .paused
            RecipeTransferRow(value: status.state == .queued ? 0 : status.fraction, caption: transferCaption) {
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

    private var transferCaption: String {
        switch status.state {
        case .queued: "Waiting…"
        case .paused: "Paused · " + status.transferCaption
        default: [status.transferCaption, speed?.summary].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var cancelButton: some View {
        ModelsIconButton(systemImage: "xmark", help: "Cancel download", action: cancel)
    }
}
