import KilnCore
import SwiftUI

/// Where models and images live on disk, and a way to free the loaded model.
struct StorageCard: View {
    @Environment(AppModel.self) private var model
    @State private var modelsSize: Int64?

    private var modelsFolder: URL { model.library.storage.root }

    private var modelsSizeText: String {
        guard let modelsSize else { return "Calculating size…" }
        return "\(modelsSize.formatted(.byteCount(style: .file))) on disk"
    }

    private var galleryCountText: String {
        let count = model.gallery.items.count
        return count == 1 ? "1 image" : "\(count) images"
    }

    var body: some View {
        SettingsCard(title: "Storage", symbol: "internaldrive", description: "Where models and images live on disk") {
            StorageFolderRow(title: "Models folder", folder: modelsFolder, badge: modelsSizeText)
            SettingsRowDivider()
            StorageFolderRow(title: "Gallery folder", folder: model.gallery.directory, badge: galleryCountText)
            SettingsRowDivider()
            SettingsRow(
                "Loaded model",
                description: Text("Unloading frees the memory the model uses. It loads again the next time you generate.")
            ) {
                Button("Unload Model") { model.generation.unloadModel() }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(model.generation.phase.isBusy)
            }
        }
        // Re-measured whenever a model is installed or deleted.
        .task(id: model.library.installedIDs) {
            let root = modelsFolder
            modelsSize = await Task.detached(priority: .utility) { DirectorySize.bytes(in: root) }.value
        }
    }
}
