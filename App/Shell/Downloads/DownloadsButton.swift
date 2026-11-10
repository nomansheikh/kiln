import KilnCore
import SwiftUI

/// The sidebar's downloads button: a progress ring that opens the list of downloads.
struct DownloadsButton: View {
    @Environment(AppModel.self) private var model
    @State private var showsDetails = false
    @State private var hovering = false

    var body: some View {
        let downloads = model.library.downloadEntries
        let overall = DownloadsOverview(downloads.map(\.status))

        Button {
            showsDetails.toggle()
        } label: {
            HStack(spacing: 10) {
                DownloadProgressRing(fraction: overall.fraction, isActive: overall.isActive)
                    .frame(width: 20, height: 20)
                Text("Downloads")
                Spacer()
                Text(overall.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                Color.primary.opacity(showsDetails ? 0.08 : (hovering ? 0.045 : 0)),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help("Show downloads")
        .popover(isPresented: $showsDetails, arrowEdge: .trailing) {
            DownloadsPopover()
                .environment(model)
        }
    }
}

/// The combined state of every download, for the button's ring and caption.
struct DownloadsOverview {
    let fraction: Double?
    let isActive: Bool
    let caption: String

    init(_ statuses: [DownloadStatus]) {
        let active = statuses.filter(\.isActive)
        isActive = !active.isEmpty
        let total = active.compactMap(\.totalBytes).reduce(0, +)
        let received = active.map(\.receivedBytes).reduce(0, +)
        fraction = isActive && total > 0 ? min(1, Double(received) / Double(total)) : nil

        if let fraction {
            caption = fraction.formatted(.percent.precision(.fractionLength(0)))
        } else if isActive {
            caption = "Starting"
        } else if statuses.contains(where: { if case .failed = $0.state { true } else { false } }) {
            caption = "Failed"
        } else if statuses.contains(where: { $0.state == .paused }) {
            caption = "Paused"
        } else {
            caption = "Done"
        }
    }
}
