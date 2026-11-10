import KilnCore
import SwiftUI

/// One download in the downloads popover: what it is, how far along, and its controls.
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(stateColor)
            }

            if showsProgress {
                ProgressView(value: status.state == .verifying ? nil : status.fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 6) {
                controls
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    private var showsProgress: Bool {
        switch status.state {
        case .queued, .downloading, .verifying, .paused: true
        case .completed, .failed: false
        }
    }

    private var stateText: String {
        switch status.state {
        case .queued: "Waiting"
        case .downloading: status.percentText ?? "Downloading"
        case .verifying: "Verifying"
        case .paused: "Paused"
        case .completed: "Ready"
        case .failed: "Failed"
        }
    }

    private var stateColor: Color {
        switch status.state {
        case .completed: .green
        case .failed: .red
        default: .secondary
        }
    }

    /// The lines under the progress bar: bytes, speed and time left, and the current file.
    private var details: [String] {
        switch status.state {
        case .failed(let message):
            return [message]
        case .completed:
            return [status.receivedBytes.formatted(.byteCount(style: .file)) + " downloaded and verified"]
        case .verifying:
            return ["Checking the files against their checksums"]
        case .queued:
            return ["Starts when the current download finishes"]
        case .downloading, .paused:
            var lines = [bytesLine]
            if status.state == .downloading {
                lines.append(speed?.summary ?? "Estimating time left…")
            }
            if let file = status.currentFile?.split(separator: "/").last {
                lines.append(String(file))
            }
            return lines
        }
    }

    private var bytesLine: String {
        let received = status.receivedBytes.formatted(.byteCount(style: .file))
        guard let total = status.totalBytes else { return "\(received) downloaded" }
        let remaining = max(0, total - status.receivedBytes).formatted(.byteCount(style: .file))
        return "\(received) of \(total.formatted(.byteCount(style: .file))) · \(remaining) remaining"
    }

    @ViewBuilder
    private var controls: some View {
        switch status.state {
        case .queued, .verifying:
            Button("Cancel", action: cancel).buttonStyle(SoftButtonStyle())
        case .downloading:
            Button("Pause", systemImage: "pause.fill", action: pause).buttonStyle(SoftButtonStyle())
            Button("Cancel", action: cancel).buttonStyle(SoftButtonStyle())
        case .paused:
            Button("Resume", systemImage: "play.fill", action: start).buttonStyle(SoftButtonStyle())
            Button("Cancel", action: cancel).buttonStyle(SoftButtonStyle())
        case .failed:
            Button("Try Again", systemImage: "arrow.clockwise", action: start).buttonStyle(SoftButtonStyle())
            Button("Dismiss", action: dismiss).buttonStyle(SoftButtonStyle())
        case .completed:
            Button("Use", systemImage: "wand.and.stars", action: use).buttonStyle(AccentButtonStyle())
            Button("Dismiss", action: dismiss).buttonStyle(SoftButtonStyle())
        }
    }
}
