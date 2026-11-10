import AppKit
import KilnCore
import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @Environment(AppModel.self) private var model

    @State private var searchText = ""
    @State private var showsDownloadedOnly = false
    @State private var isImporting = false
    @State private var importError: String?

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleRecipes: [ModelRecipe] {
        showsDownloadedOnly ? model.recipes.filter { model.isInstalled($0) } : model.recipes
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Models", subtitle: "Curated recipes and Hugging Face checkpoints") {
                HStack(spacing: 8) {
                    ModelsSearchField(text: $searchText)
                    DownloadedChip(isOn: $showsDownloadedOnly)
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import Recipe", systemImage: "square.and.arrow.down")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(SoftButtonStyle())
                    .help("Add a model recipe from a JSON file")
                }
            }
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)

            Group {
                if query.isEmpty {
                    recipeList
                } else {
                    HubSearchResults(query: query)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importRecipe(result)
        }
        .alert("Could Not Import Recipe", isPresented: isPresenting($importError)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private var recipeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !model.recipeProblems.isEmpty {
                    RecipeProblemsView(problems: model.recipeProblems)
                }
                if visibleRecipes.isEmpty {
                    emptyState
                } else {
                    ModelsSectionTitle(
                        text: showsDownloadedOnly ? "Downloaded" : "Recommended",
                        count: visibleRecipes.count
                    )
                    ForEach(visibleRecipes) { recipe in
                        RecipeCard(recipe: recipe)
                    }
                }
            }
            .frame(maxWidth: Theme.contentWidth)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if showsDownloadedOnly {
            ContentUnavailableView(
                "No Downloaded Models",
                systemImage: "arrow.down.circle",
                description: Text("Turn off the Downloaded filter to see models you can get.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            ContentUnavailableView(
                "No Recipes",
                systemImage: "shippingbox",
                description: Text("Import a recipe, or search Hugging Face for a checkpoint.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }

    private func importRecipe(_ result: Result<URL, any Error>) {
        do {
            let file = try result.get()
            let scoped = file.startAccessingSecurityScopedResource()
            defer {
                if scoped { file.stopAccessingSecurityScopedResource() }
            }
            try model.importRecipe(from: file)
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// A binding that is true while the optional message holds a value.
@MainActor
private func isPresenting(_ message: Binding<String?>) -> Binding<Bool> {
    Binding(
        get: { message.wrappedValue != nil },
        set: { if !$0 { message.wrappedValue = nil } }
    )
}

// MARK: - Header controls

private struct ModelsSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Hugging Face", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 250)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(isFocused ? Theme.accent.opacity(0.7) : Theme.hairline))
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .background(
            // Command-F jumps to the search field.
            Button("Search") { isFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }
}

private struct DownloadedChip: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "arrow.down.circle")
                    .imageScale(.small)
                Text("Downloaded")
            }
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isOn ? Theme.accent : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isOn ? Theme.accent.opacity(0.14) : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Theme.accent.opacity(0.5) : Theme.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show only models that are on this Mac")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Shared pieces for the Models screen

/// Small secondary heading above a group of cards.
struct ModelsSectionTitle: View {
    let text: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
        .padding(.leading, 2)
    }
}

/// A quiet chevron row that opens and closes a section inside a card.
struct ModelsDisclosureRow: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// Quiet neutral tile with the owner's initial, in place of a colourful avatar.
struct ModelsMonogram: View {
    let name: String
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Theme.hairline))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.first { $0.isLetter || $0.isNumber } ?? "?").uppercased())
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            )
            .accessibilityHidden(true)
    }
}

/// Compact icon-only secondary button.
struct ModelsIconButton: View {
    let systemImage: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(width: 14, height: 17)
        }
        .buttonStyle(SoftButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

extension View {
    /// The shared card with a subtle highlight while the pointer is over it.
    func modelsCard(hovering: Bool) -> some View {
        self
            .card(padding: 18)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.025 : 0))
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    /// Inset rounded surface that holds file rows inside a card.
    func modelsInsetSurface() -> some View {
        self
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
    }
}

// MARK: - Recipe problems

private struct RecipeProblemsView: View {
    let problems: [RecipeStore.LoadFailure]
    @State private var isExpanded = false

    private var title: String {
        problems.count == 1 ? "1 recipe could not be loaded" : "\(problems.count) recipes could not be loaded"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Text(title)
                        .font(.callout.weight(.medium))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(problems.enumerated()), id: \.element.file) { index, problem in
                        if index > 0 {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(problem.file.lastPathComponent)
                                .font(.caption.monospaced().weight(.medium))
                            Text(problem.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                }
                .modelsInsetSurface()
            }
        }
        .card(padding: 12)
    }
}

// MARK: - Recipe card

private struct RecipeCard: View {
    @Environment(AppModel.self) private var model
    let recipe: ModelRecipe

    @State private var hovering = false
    @State private var showsFiles = false
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    private var repos: [String] {
        var seen: Set<String> = []
        return recipe.components.map(\.repo).filter { seen.insert($0).inserted }
    }

    private var owners: [String] {
        var seen: Set<String> = []
        return repos
            .map { $0.split(separator: "/").first.map(String.init) ?? $0 }
            .filter { seen.insert($0).inserted }
    }

    private var fileCount: String {
        recipe.components.count == 1 ? "1 file" : "\(recipe.components.count) files"
    }

    var body: some View {
        let status = model.downloadStatus(for: recipe)
        // A finished download counts as installed; the installed set catches up a moment later.
        let installed = model.isInstalled(recipe) || status?.state == .completed

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ModelsMonogram(name: owners.first ?? recipe.name)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(recipe.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if installed {
                            Pill(text: "Installed", systemImage: "checkmark.circle.fill", tint: .green)
                                .fixedSize()
                        }
                    }
                    Text(owners.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(repos.joined(separator: "\n"))
                }
                Spacer(minLength: 12)
                if installed {
                    installedActions
                } else if status == nil {
                    downloadButton
                }
            }

            HStack(spacing: 6) {
                if let size = recipe.totalSizeBytes {
                    Pill(text: size.formatted(.byteCount(style: .file)), systemImage: "internaldrive")
                        .help("Total download size")
                }
                Pill(text: fileCount, systemImage: "doc.on.doc")
                Pill(text: "\(recipe.defaults.width) × \(recipe.defaults.height)", systemImage: "aspectratio")
                    .help("Default resolution")
                Pill(text: "\(recipe.defaults.steps) steps", systemImage: "bolt")
                    .help("Default step count")
                if let fit = model.fit(for: recipe) {
                    FitLabel(fit: fit, memoryGB: Int(model.memory.physicalMemoryGB.rounded()))
                        .padding(.leading, 6)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)

            if let note = recipe.licenseNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .help(note)
            }

            if !installed, let status {
                transfer(status)
            }

            ModelsDisclosureRow(title: "Files", isExpanded: $showsFiles)
            if showsFiles {
                VStack(spacing: 0) {
                    ForEach(Array(recipe.components.enumerated()), id: \.element.role) { index, component in
                        if index > 0 {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                        ComponentRow(component: component)
                    }
                }
                .modelsInsetSurface()
            }
        }
        .modelsCard(hovering: hovering)
        .onHover { hovering = $0 }
    }

    // MARK: Actions

    private var installedActions: some View {
        HStack(spacing: 8) {
            ModelsIconButton(systemImage: "trash", help: "Delete this model's files", role: .destructive) {
                isConfirmingDelete = true
            }
            .accessibilityLabel("Delete \(recipe.name)")
            .confirmationDialog("Delete \(recipe.name)?", isPresented: $isConfirmingDelete) {
                Button("Delete Files", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The downloaded files are removed from this Mac. You can download the model again later.")
            }
            .alert("Could Not Delete Model", isPresented: isPresenting($deleteError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }

            Button {
                model.selectRecipe(recipe)
                model.selection = .generate
            } label: {
                Label("Use", systemImage: "wand.and.stars")
            }
            .buttonStyle(AccentButtonStyle())
            .help("Generate images with this model")
        }
        .fixedSize()
    }

    @ViewBuilder
    private var downloadButton: some View {
        if model.fit(for: recipe) == .tooLarge {
            Button {
                model.download(recipe)
            } label: {
                Label("Download", systemImage: "arrow.down")
            }
            .buttonStyle(SoftButtonStyle())
            .fixedSize()
            .help("This model needs more memory than this Mac has and may not run.")
        } else {
            Button {
                model.download(recipe)
            } label: {
                Label("Download", systemImage: "arrow.down")
            }
            .buttonStyle(AccentButtonStyle())
            .fixedSize()
        }
    }

    // MARK: Transfer

    @ViewBuilder
    private func transfer(_ status: DownloadStatus) -> some View {
        switch status.state {
        case .queued:
            transferRow(value: 0, caption: "Waiting…") {
                ModelsIconButton(systemImage: "xmark", help: "Cancel download") { model.cancelDownload(recipe) }
            }
        case .downloading:
            transferRow(value: status.fraction, caption: transferCaption(status)) {
                ModelsIconButton(systemImage: "pause.fill", help: "Pause download") { model.pauseDownload(recipe) }
                ModelsIconButton(systemImage: "xmark", help: "Cancel download") { model.cancelDownload(recipe) }
            }
        case .verifying:
            transferRow(value: nil, caption: "Verifying…") { EmptyView() }
        case .paused:
            transferRow(value: status.fraction, caption: "Paused · " + transferCaption(status)) {
                ModelsIconButton(systemImage: "play.fill", help: "Resume download") { model.download(recipe) }
                ModelsIconButton(systemImage: "xmark", help: "Cancel download") { model.cancelDownload(recipe) }
            }
        case .failed(let message):
            HStack(alignment: .center, spacing: 12) {
                Label {
                    Text(message)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    ModelsIconButton(systemImage: "arrow.clockwise", help: "Retry download") { model.download(recipe) }
                    ModelsIconButton(systemImage: "xmark", help: "Dismiss") { model.dismissDownload(recipe) }
                }
                .fixedSize()
            }
            .padding(10)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .completed:
            EmptyView()
        }
    }

    private func transferRow(
        value: Double?,
        caption: String,
        @ViewBuilder buttons: () -> some View
    ) -> some View {
        // The buttons share a row with the bar so they centre on it; the caption sits below both.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                ProgressView(value: value)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 6) {
                    buttons()
                }
                .fixedSize()
            }
            Text(caption)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(caption)
        }
    }

    /// "4.2 GB of 17 GB · 25% · filename", leaving out whatever is unknown.
    private func transferCaption(_ status: DownloadStatus) -> String {
        var caption = status.receivedBytes.formatted(.byteCount(style: .file))
        if let total = status.totalBytes {
            caption += " of " + total.formatted(.byteCount(style: .file))
        }
        if let fraction = status.fraction {
            caption += " · " + fraction.formatted(.percent.precision(.fractionLength(0)))
        }
        if let file = status.currentFile?.split(separator: "/").last {
            caption += " · " + String(file)
        }
        return caption
    }

    private func delete() {
        do {
            try model.deleteModel(recipe)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

private struct ComponentRow: View {
    let component: ModelRecipe.Component

    var body: some View {
        HStack(spacing: 10) {
            Text(component.role.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
            Text(component.file)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .help("\(component.repo)/\(component.file)")
            Spacer(minLength: 8)
            if let size = component.sizeBytes {
                Text(size.formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}
