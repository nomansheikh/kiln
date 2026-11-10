import KilnCore
import SwiftUI

/// The progress and controls of a recipe download, for whichever state the transfer is in.
struct RecipeTransferView: View {
    let status: DownloadStatus
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
        case .downloading:
            RecipeTransferRow(value: status.fraction, caption: status.transferCaption) {
                ModelsIconButton(systemImage: "pause.fill", help: "Pause download", action: pause)
                cancelButton
            }
        case .verifying:
            RecipeTransferRow(value: nil, caption: "Verifying…") { EmptyView() }
        case .paused:
            RecipeTransferRow(value: status.fraction, caption: "Paused · " + status.transferCaption) {
                ModelsIconButton(systemImage: "play.fill", help: "Resume download", action: download)
                cancelButton
            }
        case .failed(let message):
            RecipeTransferFailure(message: message, retry: download, dismiss: dismiss)
        case .completed:
            EmptyView()
        }
    }

    private var cancelButton: some View {
        ModelsIconButton(systemImage: "xmark", help: "Cancel download", action: cancel)
    }
}
