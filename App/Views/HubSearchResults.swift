import AppKit
import KilnCore
import SwiftUI

/// Hugging Face search results shown on the Models screen while the user types.
struct HubSearchResults: View {
    @Environment(AppModel.self) private var model

    private let query: String

    @State private var phase: SearchPhase = .loading
    @State private var attempt = 0
    @State private var infos: [String: HFModelInfo] = [:]
    @State private var loadingRepos: Set<String> = []
    @State private var failures: [String: RepoFailure] = [:]
    @State private var downloadError: String?

    init(query: String) {
        self.query = query
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: SearchKey(query: query, attempt: attempt)) { await search() }
            .alert("Download could not start", isPresented: downloadErrorIsPresented, presenting: downloadError) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching Hugging Face…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Search failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button {
                    attempt += 1
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SoftButtonStyle())
            }
        case .results(let summaries) where summaries.isEmpty:
            ContentUnavailableView.search(text: query)
        case .results(let summaries):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ModelsSectionTitle(text: "Hugging Face results", count: summaries.count)
                    ForEach(summaries) { summary in
                        HubResultCard(
                            summary: summary,
                            info: infos[summary.id],
                            isLoading: loadingRepos.contains(summary.id),
                            failure: failures[summary.id],
                            loadFiles: { loadInfo(for: summary.id) },
                            download: download
                        )
                    }
                }
                .frame(maxWidth: Theme.contentWidth)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var downloadErrorIsPresented: Binding<Bool> {
        Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })
    }

    private func search() async {
        phase = .loading
        do {
            try await Task.sleep(for: .milliseconds(350))
            let summaries = try await model.hub.searchModels(query: query)
            guard !Task.isCancelled else { return }
            phase = .results(summaries)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    private func loadInfo(for repo: String) {
        guard infos[repo] == nil, !loadingRepos.contains(repo) else { return }
        loadingRepos.insert(repo)
        failures[repo] = nil
        Task {
            do {
                infos[repo] = try await model.hub.modelInfo(repo: repo)
            } catch {
                var needsToken = false
                if let hubError = error as? HFError {
                    switch hubError {
                    case .accessDenied, .unauthorized: needsToken = true
                    default: break
                    }
                }
                failures[repo] = RepoFailure(message: Self.message(for: error), needsToken: needsToken)
            }
            loadingRepos.remove(repo)
        }
    }

    private func download(_ file: HFFile, in info: HFModelInfo) {
        do {
            try model.downloadFromHub(file, in: info)
        } catch {
            downloadError = Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private enum SearchPhase {
    case loading
    case results([HFModelSummary])
    case failed(String)
}

/// Bumping `attempt` restarts the search task for the same query.
private struct SearchKey: Equatable {
    var query: String
    var attempt: Int
}

private struct RepoFailure {
    var message: String
    var needsToken: Bool
}

// MARK: - Card

private struct HubResultCard: View {
    let summary: HFModelSummary
    let info: HFModelInfo?
    let isLoading: Bool
    let failure: RepoFailure?
    let loadFiles: () -> Void
    let download: (HFFile, HFModelInfo) -> Void

    @State private var isExpanded = false
    @State private var hovering = false

    private var repoName: String {
        summary.id.split(separator: "/").last.map(String.init) ?? summary.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ModelsMonogram(name: summary.author.isEmpty ? repoName : summary.author)
                VStack(alignment: .leading, spacing: 3) {
                    Text(repoName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(summary.id)
                    Text(summary.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if let url = URL(string: "https://huggingface.co/\(summary.id)") {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text("Open on Hugging Face")
                            Image(systemName: "arrow.up.right")
                                .imageScale(.small)
                        }
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                    }
                    .foregroundStyle(.secondary)
                    .help(url.absoluteString)
                }
            }

            HStack(spacing: 6) {
                Pill(text: summary.downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
                    .help("Downloads")
                Pill(text: summary.likes.formatted(.number.notation(.compactName)), systemImage: "heart")
                    .help("Likes")
                if let license = summary.license {
                    Pill(text: license, systemImage: "doc.text")
                        .help("License")
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)

            ModelsDisclosureRow(title: "Files", isExpanded: $isExpanded)
            if isExpanded {
                HubFileList(info: info, isLoading: isLoading, failure: failure, retry: loadFiles, download: download)
            }
        }
        .modelsCard(hovering: hovering)
        .onHover { hovering = $0 }
        .onChange(of: isExpanded) { _, expanded in
            if expanded { loadFiles() }
        }
    }
}

// MARK: - Files

private struct HubFileList: View {
    @Environment(AppModel.self) private var model

    let info: HFModelInfo?
    let isLoading: Bool
    let failure: RepoFailure?
    let retry: () -> Void
    let download: (HFFile, HFModelInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info {
                loaded(info)
            } else if let failure {
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
            } else if isLoading {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
            VStack(spacing: 0) {
                ForEach(files) { file in
                    if file.id != files.first?.id {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    HubFileRow(file: file, info: info) { download(file, info) }
                }
            }
            .modelsInsetSurface()
        }
        Text("Downloading a single file only works for all-in-one checkpoints, for example SD 1.5 or SDXL .safetensors. Models split into several parts need a recipe.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HubFileRow: View {
    @Environment(AppModel.self) private var model

    let file: HFFile
    let info: HFModelInfo
    let download: () -> Void

    private var recipe: ModelRecipe? {
        model.recipes.first { recipe in
            recipe.components.contains { $0.repo == info.id && $0.file == file.path }
        }
    }

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
                FitLabel(fit: fit, memoryGB: Int(model.memory.physicalMemoryGB.rounded()), compact: true)
            }
            status
                .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    /// Same thresholds as `MemoryFitEstimator`, applied to this one file.
    private var fit: MemoryFit? {
        guard let size = file.sizeBytes else { return nil }
        let required = Double(size)
        let usable = model.memory.usableBytes
        if required <= usable * 0.85 {
            return .comfortable
        }
        return required <= usable ? .tight : .tooLarge
    }

    @ViewBuilder
    private var status: some View {
        if let recipe, model.isInstalled(recipe) {
            Pill(text: "Installed", systemImage: "checkmark.circle.fill", tint: .green)
                .fixedSize()
        } else if let recipe, let status = model.downloadStatus(for: recipe), status.isActive {
            HStack(spacing: 6) {
                ProgressView(value: status.state == .downloading ? status.fraction : nil)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 56)
                if status.state == .downloading, let fraction = status.fraction {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .help(status.state == .verifying ? "Verifying…" : status.state == .queued ? "Waiting…" : "Downloading…")
        } else {
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
}
