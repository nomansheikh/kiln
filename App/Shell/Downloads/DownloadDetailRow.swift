import KilnCore
import SwiftUI

/// One download in the downloads popover. While it is transferring: its name,
/// a progress bar with its controls, and a line saying where it stands. Once
/// it has ended there is no bar, so the name and the line sit beside the buttons.
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
        Group {
            if hasEnded {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        title
                        detailLine
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 6) { controls }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    title
                    HStack(spacing: 6) {
                        progress
                        controls
                    }
                    detailLine
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Pieces

    private var isFailed: Bool {
        if case .failed = status.state { true } else { false }
    }

    /// Finished or failed: nothing is transferring, so there is no progress to show.
    private var hasEnded: Bool {
        status.state == .completed || isFailed
    }

    private var title: some View {
        Text(name)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .help(name)
    }

    private var detailLine: some View {
        HStack(spacing: 4) {
            if status.state == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text(detail)
                .foregroundStyle(isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .monospacedDigit()
                .lineLimit(isFailed ? 3 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
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
            EmptyView()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch status.state {
        case .queued, .downloading, .paused:
            // One button for all three, so its symbol morphs between pause and play.
            // Resuming passes through queued, which must keep the same button for that to happen.
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
