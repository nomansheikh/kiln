import KilnCore
import SwiftUI

/// The files of one Hugging Face repo, or the loading or failure state while there is no list yet.
struct HubFileList: View {
    @Environment(AppModel.self) private var model

    let info: HFModelInfo?
    let isLoading: Bool
    let failure: HubRepoFailure?
    let retry: () -> Void
    let download: (HFFile, HFModelInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info {
                loaded(info)
            } else if let failure {
                failed(failure)
            } else if isLoading {
                loading
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loaded(_ info: HFModelInfo) -> some View {
        let files = info.weightFiles.filter { !$0.isVisionProjector }
        if info.isGated {
            Label("This repo needs its terms accepted on Hugging Face and an access token in Settings.", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if files.isEmpty {
            Text("This repo has no single-file weights Kiln can download.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(14)
                .modelsInsetSurface()
        } else {
            rows(files, in: info)
        }
        Text(footnote(for: info))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footnote(for info: HFModelInfo) -> String {
        if let base = model.library.familyRecipe(for: info) {
            return "Each download here is one version of the model. Kiln adds the other files and the settings from its \(base.name) recipe."
        }
        return "Only a file that holds a whole model can be downloaded by itself. Files marked as a part of a model work only through a recipe."
    }

    private func rows(_ files: [HFFile], in info: HFModelInfo) -> some View {
        let library = model.library
        let hasFamily = library.familyRecipe(for: info) != nil
        let memory = library.memory
        return VStack(spacing: 0) {
            ForEach(files) { file in
                if file.id != files.first?.id {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                HubFileRow(
                    file: file,
                    availability: library.availability(of: file, in: info),
                    isRunnable: file.looksLikeStandaloneCheckpoint || (hasFamily && file.looksLikeDenoiser),
                    fit: file.sizeBytes.map { memory.fit(forFileOfSize: $0) },
                    memoryGB: Int(memory.physicalMemoryGB.rounded()),
                    download: { download(file, info) }
                )
            }
        }
        .modelsInsetSurface()
    }

    // MARK: - Failed and loading

    private func failed(_ failure: HubRepoFailure) -> some View {
        VStack(spacing: 8) {
            Label(failure.message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                if failure.needsToken {
                    Button {
                        model.selection = .settings
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                    }
                }
                Button(action: retry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(SoftButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .modelsInsetSurface()
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading files…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .modelsInsetSurface()
    }
}
