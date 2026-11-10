import KilnCore
import SwiftUI

/// One downloadable weights file of a Hugging Face repo.
struct HubFileRow: View {
    let file: HFFile
    let availability: HubFileAvailability
    /// How well the file fits this Mac's memory, when its size is known.
    let fit: MemoryFit?
    let memoryGB: Int
    let download: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // The full path, because multi-folder repos repeat the same file name.
            Text(file.path)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .help(file.path)
            if let quantization = file.quantization {
                Pill(text: quantization)
                    .fixedSize()
            }
            Spacer(minLength: 12)
            if let size = file.sizeBytes {
                Text(size.formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if let fit {
                FitLabel(fit: fit, memoryGB: memoryGB, compact: true)
            }
            trailingControl
                .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Trailing control

    @ViewBuilder
    private var trailingControl: some View {
        switch availability {
        case .installed:
            Pill(text: "Installed", systemImage: "checkmark.circle.fill", tint: .green)
                .fixedSize()
        case .transferring(let status):
            progress(status)
        case .available:
            Button(action: download) {
                Label("Download", systemImage: "arrow.down")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, -4)
                    .padding(.vertical, -2)
            }
            .buttonStyle(AccentButtonStyle())
            .fixedSize()
        }
    }

    private func progress(_ status: DownloadStatus) -> some View {
        let isDownloading = status.state == .downloading
        return HStack(spacing: 6) {
            ProgressView(value: isDownloading ? status.fraction : nil)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .frame(width: 56)
            if isDownloading, let percent = status.percentText {
                Text(percent)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .help(status.state == .verifying ? "Verifying…" : status.state == .queued ? "Waiting…" : "Downloading…")
    }
}
