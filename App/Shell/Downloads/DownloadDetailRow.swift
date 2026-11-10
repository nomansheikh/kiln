import KilnCore
import SwiftUI

/// One download in the downloads popover: its name, a progress bar with
/// its controls, and a single line saying where it stands.
struct DownloadDetailRow: View {
    let name: String
    let status: DownloadStatus
    let speed: DownloadSpeed?
    /// Starts, resumes or retries the download.
    let start: () -> Void
    let pause: () -> Void
    let cancel: () -> Void
    /// Removes a finished or failed entry from the list.
    let dismiss: () -> Void
    let use: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(name)

            HStack(spacing: 6) {
                progress
                controls
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .monospacedDigit()
                .lineLimit(isFailed ? 3 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Pieces

    private var isFailed: Bool {
        if case .failed = status.state { true } else { false }
    }

    @ViewBuilder
    private var progress: some View {
        switch status.state {
        case .queued, .downloading, .paused:
            ProgressView(value: status.fraction ?? 0)
                .progressViewStyle(.linear)
                .tint(status.state == .paused ? .secondary : Theme.accent)
        case .verifying:
            ProgressView()
                .progressViewStyle(.linear)
                .tint(Theme.accent)
        case .completed, .failed:
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch status.state {
        case .queued:
            RoundIconButton(systemImage: "xmark", help: "Cancel", action: cancel)
        case .downloading, .paused:
            // One button for both states, so its symbol morphs between pause and play.
            let isPaused = status.state == .paused
            RoundIconButton(
                systemImage: isPaused ? "play.fill" : "pause.fill",
                help: isPaused ? "Resume" : "Pause",
                action: isPaused ? start : pause
            )
            RoundIconButton(systemImage: "xmark", help: "Cancel", action: cancel)
        case .verifying:
            EmptyView()
        case .failed:
            RoundIconButton(systemImage: "arrow.clockwise", help: "Try again", action: start)
            RoundIconButton(systemImage: "xmark", help: "Dismiss", action: dismiss)
        case .completed:
            Button("Use", action: use)
                .buttonStyle(AccentButtonStyle())
                .controlSize(.small)
                .focusable(false)
            RoundIconButton(systemImage: "xmark", help: "Dismiss", action: dismiss)
        }
    }

    /// One line: how much, how fast, how long. For example "4.2 GB of 8.7 GB · 18 MB/s · 4 min left".
    private var detail: String {
        let received = status.receivedBytes.formatted(.byteCount(style: .file))
        let amount = status.totalBytes.map { "\(received) of \($0.formatted(.byteCount(style: .file)))" } ?? received
        switch status.state {
        case .queued:
            return "Waiting for the current download"
        case .downloading:
            return [amount, speed?.speedText, speed?.shortRemainingText].compactMap { $0 }.joined(separator: " · ")
        case .paused:
            return "Paused · \(amount)"
        case .verifying:
            return "Verifying…"
        case .completed:
            return "Ready · \(received)"
        case .failed(let message):
            return message
        }
    }
}
