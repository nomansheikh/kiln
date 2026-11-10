import AppKit
import SwiftUI

/// A folder with its path, a size or count badge, and a reveal button.
struct StorageFolderRow: View {
    let title: String
    let folder: URL
    let badge: String

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .fontWeight(.medium)
                    Pill(text: badge)
                }
                Text(verbatim: folder.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(folder.path)
            }
            Spacer(minLength: 0)
            Button("Show in Finder", action: showInFinder)
                .buttonStyle(SoftButtonStyle())
                .fixedSize()
        }
    }

    /// Creates the folder first, so there is always something to reveal.
    private func showInFinder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
