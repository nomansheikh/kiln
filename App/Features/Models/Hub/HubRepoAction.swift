import KilnCore
import SwiftUI

/// The single control on a Hugging Face model card: download it, watch it
/// download, use it, or learn that it is not supported yet.
struct HubRepoAction: View {
    @Environment(AppModel.self) private var model
    let support: HubRepoSupport
    let download: (HFFile, HFModelInfo) -> Void

    var body: some View {
        switch support {
        case .recipe, .unavailable:
            // A recipe has its own banner; a failed load is explained under Files.
            EmptyView()
        case .checking:
            ProgressView()
                .controlSize(.small)
                .help("Checking what this model needs")
        case .unsupported:
            Pill(text: "No recipe yet", systemImage: "puzzlepiece.extension")
                .fixedSize()
                .help("This model comes in several files. Kiln needs a recipe to put them together, and does not have one yet.")
        case .checkpoint(let file, let info):
            fileControl(file, info, help: "Downloads \(file.name), the complete model in one file")
        case .family(let file, let info, let base):
            fileControl(file, info, help: "Downloads \(file.name) and the other files it needs from Kiln's \(base.name) recipe")
        }
    }

    @ViewBuilder
    private func fileControl(_ file: HFFile, _ info: HFModelInfo, help: String) -> some View {
        let library = model.library
        switch library.availability(of: file, in: info) {
        case .installed:
            Button {
                if let recipe = library.recipe(for: file, in: info) { model.use(recipe) }
            } label: {
                Label("Use", systemImage: "wand.and.stars")
            }
            .buttonStyle(AccentButtonStyle())
        case .transferring(let status):
            Text(status.state == .verifying ? "Verifying…" : status.percentText ?? "Starting…")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .available:
            HStack(spacing: 8) {
                if let size = file.sizeBytes {
                    Text(size.formatted(.byteCount(style: .file)))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button {
                    download(file, info)
                } label: {
                    Label("Download", systemImage: "arrow.down")
                }
                .buttonStyle(AccentButtonStyle())
                .help(help)
            }
            .fixedSize()
        }
    }
}
