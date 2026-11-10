import KilnCore
import SwiftUI

/// One curated model on the Models screen: what it is, whether it fits this Mac,
/// and the controls to download, use or delete it.
struct RecipeCard: View {
    @Environment(AppModel.self) private var model
    let recipe: ModelRecipe

    @State private var hovering = false
    @State private var showsFiles = false

    var body: some View {
        let library = model.library
        let status = library.downloadStatus(for: recipe)
        // A finished download counts as installed; the installed set catches up a moment later.
        let installed = library.isInstalled(recipe) || status?.state == .completed

        VStack(alignment: .leading, spacing: 12) {
            header(installed: installed, status: status)
            specs

            if let note = recipe.licenseNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .help(note)
            }

            if recipe.isIncompleteSingleFile {
                RecipeIncompleteNotice { try? library.removeRecipe(recipe) }
            }

            if !installed, let status {
                RecipeTransferView(
                    status: status,
                    speed: library.downloadSpeeds[recipe.id],
                    download: { library.download(recipe) },
                    pause: { library.pauseDownload(recipe) },
                    cancel: { library.cancelDownload(recipe) },
                    dismiss: { library.dismissDownload(recipe) }
                )
            }

            ModelsDisclosureRow(title: "Files", isExpanded: $showsFiles)
            if showsFiles {
                RecipeFileList(components: recipe.components)
            }
        }
        .modelsCard(hovering: hovering)
        .onHover { hovering = $0 }
    }

    // MARK: - Header

    private func header(installed: Bool, status: DownloadStatus?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ModelsMonogram(name: recipe.sourceOwners.first ?? recipe.name)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(recipe.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if recipe.isIncompleteSingleFile {
                        Pill(text: "Part of a model", systemImage: "puzzlepiece.extension", tint: .orange)
                            .fixedSize()
                    } else if installed {
                        Pill(text: "Installed", systemImage: "checkmark.circle.fill", tint: .green)
                            .fixedSize()
                    }
                }
                Text(recipe.sourceOwners.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(recipe.sourceRepos.joined(separator: "\n"))
            }
            Spacer(minLength: 12)
            if recipe.isIncompleteSingleFile {
                // Nothing to use or download: the notice below explains and offers removal.
                EmptyView()
            } else if installed {
                RecipeInstalledActions(
                    recipeName: recipe.name,
                    delete: { try model.library.deleteModel(recipe) },
                    use: { model.use(recipe) }
                )
            } else if status == nil {
                RecipeDownloadButton(isTooLarge: model.library.fit(for: recipe) == .tooLarge) {
                    model.library.download(recipe)
                }
            }
        }
    }

    // MARK: - Specs

    private var specs: some View {
        HStack(spacing: 6) {
            if let size = recipe.totalSizeBytes {
                Pill(text: size.formatted(.byteCount(style: .file)), systemImage: "internaldrive")
                    .help("Total download size")
            }
            Pill(text: recipe.fileCountText, systemImage: "doc.on.doc")
            Pill(text: "\(recipe.defaults.width) × \(recipe.defaults.height)", systemImage: "aspectratio")
                .help("Default resolution")
            Pill(text: "\(recipe.defaults.steps) steps", systemImage: "bolt")
                .help("Default step count")
            if let fit = model.library.fit(for: recipe) {
                FitLabel(fit: fit, memoryGB: Int(model.library.memory.physicalMemoryGB.rounded()))
                    .padding(.leading, 6)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }
}
