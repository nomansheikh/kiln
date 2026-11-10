import AppKit
import KilnCore
import SwiftUI
import UniformTypeIdentifiers

struct GenerateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Hero: nothing to show yet, so the composer sits centred under a headline.
        let isHero = model.latestImage == nil && !model.phase.isBusy
        let hasModels = !model.installedRecipes.isEmpty

        VStack(spacing: 0) {
            HStack {
                ModelPill()
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.leading, 14)

            if isHero {
                Spacer(minLength: 24)
                Text("What do you want to create?")
                    .font(Theme.roundedTitle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            } else {
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }

            VStack(spacing: 12) {
                if case .failed(let message) = model.phase {
                    ErrorCard(message: message)
                        .transition(.opacity)
                }
                Composer()
                    .disabled(!hasModels && !model.phase.isBusy)
            }
            .frame(maxWidth: isHero ? 560 : 720)
            .padding(.horizontal, 24)
            .padding(.bottom, isHero ? 0 : 18)

            if isHero {
                Group {
                    if hasModels {
                        SuggestionChips()
                    } else {
                        NoModelsHint()
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .transition(.opacity)
                // Slightly more space below than above lifts the group to the optical centre.
                Spacer(minLength: 24)
                Spacer(minLength: 0).frame(maxHeight: 56)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy, value: isHero)
        .animation(.snappy, value: model.phase.isFailed)
    }

    @ViewBuilder
    private var canvas: some View {
        if model.phase.isBusy {
            GenerationProgressView(
                phase: model.phase,
                prompt: model.draft.prompt,
                aspectRatio: CGFloat(max(model.draft.width, 1)) / CGFloat(max(model.draft.height, 1))
            )
        } else if let item = model.latestImage {
            ResultView(item: item)
        }
    }
}

private extension GenerationPhase {
    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }
}

// MARK: - Model selector

/// The capsule in the top-left corner that names the current model and switches it.
private struct ModelPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.installedRecipes.isEmpty {
            Button { model.selection = .models } label: {
                label("No model")
            }
            .buttonStyle(.plain)
            .help("Download a model")
        } else {
            // A Menu of Buttons rather than a Picker so every change goes through selectRecipe(_:).
            Menu {
                ForEach(model.installedRecipes) { recipe in
                    Button { model.selectRecipe(recipe) } label: {
                        if recipe.id == model.draft.recipeID {
                            Label(recipe.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: recipe.name)
                        }
                    }
                }
            } label: {
                label(model.selectedRecipe?.name ?? "No model")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Model")
        }
    }

    private func label(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cube")
                .foregroundStyle(.secondary)
            Text(verbatim: name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 260)
                .fixedSize()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .contentShape(Capsule())
    }
}

// MARK: - Hero

private struct Suggestion: Identifiable {
    let title: String
    let prompt: String

    var id: String { title }

    static let all = [
        Suggestion(
            title: "Misty alpine lake",
            prompt: "A misty alpine lake at dawn, pine forest reflected in still water, soft golden light, wide landscape photograph"
        ),
        Suggestion(
            title: "Watercolour cafe",
            prompt: "A cosy corner cafe on a rainy evening, warm window light, loose watercolour illustration with soft edges"
        ),
        Suggestion(
            title: "Neon city at night",
            prompt: "A rain-soaked city street at night, neon signs reflected in puddles, cinematic lighting, shallow depth of field"
        ),
        Suggestion(
            title: "Fox portrait",
            prompt: "A studio portrait of a red fox, detailed fur, dramatic rim lighting, dark background, 85mm lens"
        ),
    ]
}

private struct SuggestionChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Suggestion.all) { suggestion in
                SuggestionChip(suggestion: suggestion) {
                    model.draft.prompt = suggestion.prompt
                }
            }
        }
    }
}

private struct SuggestionChip: View {
    let suggestion: Suggestion
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(suggestion.title)
                .lineLimit(1)
                .font(.callout)
                .foregroundStyle(hovering ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(hovering ? Theme.card : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(suggestion.prompt)
    }
}

private struct NoModelsHint: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Text("No models installed yet.")
                .foregroundStyle(.secondary)
            Button("Download a model") { model.selection = .models }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}

/// A 28 pt round grey button face holding one symbol.
private struct RoundIcon: View {
    let systemImage: String
    var active = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(active ? 0.1 : 0.06), in: Circle())
            .contentShape(Circle())
    }
}

/// Lays children out in centred rows, wrapping when a row is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX + max((bounds.width - row.width) / 2, 0)
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
}

// MARK: - Result

private struct ResultView: View {
    @Environment(AppModel.self) private var model
    let item: GalleryItem
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
                        .shadow(color: .black.opacity(0.10), radius: 16, y: 4)
                        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                        .transition(.opacity)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(verbatim: item.record.request.prompt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: 620)

            HStack(spacing: 8) {
                Button { model.copyToPasteboard(item) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button { saveAs() } label: {
                    Label("Save As…", systemImage: "square.and.arrow.down")
                }
                ShareLink(item: item.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button { model.revealInFinder(item) } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            .buttonStyle(SoftButtonStyle())
            .lineLimit(1)

            FlowLayout(spacing: 6) {
                Pill(text: item.record.recipeName, systemImage: "cube")
                Pill(text: "\(request.width) × \(request.height)", systemImage: "aspectratio")
                Pill(text: "\(request.steps) steps", systemImage: "square.stack.3d.up")
                Pill(text: "Seed \(request.seed)", systemImage: "dice")
                if let seconds = item.record.durationSeconds {
                    Pill(text: "\(seconds.formatted(.number.precision(.fractionLength(1)))) s", systemImage: "timer")
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .textSelection(.enabled)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .task(id: item.id) {
            image = NSImage(contentsOf: item.url)
        }
    }

    private var request: GenerationRequest { item.record.request }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = item.url.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            // The panel already asked before replacing an existing file.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: item.url, to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

// MARK: - Progress

private struct GenerationProgressView: View {
    let phase: GenerationPhase
    let prompt: String
    let aspectRatio: CGFloat

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface)
                Shimmer()
                status
                    .padding(24)
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.06), radius: 16, y: 4)
            .frame(maxWidth: 560, maxHeight: 560)

            if !prompt.isEmpty {
                Text(verbatim: prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 560)
            }
        }
        .padding(28)
    }

    private var status: some View {
        VStack(spacing: 10) {
            Text(verbatim: title)
                .font(.headline)

            if let detail {
                Text(verbatim: detail)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Group {
                if let fraction {
                    ProgressView(value: min(max(fraction, 0), 1))
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .controlSize(.small)
            .tint(Theme.accent)
            .frame(maxWidth: 220)
            .padding(.top, 4)
        }
    }

    private var fraction: Double? {
        if case .running(let progress) = phase { progress.fraction } else { nil }
    }

    private var title: String {
        switch phase {
        case .idle, .failed: ""
        case .starting: "Starting…"
        case .loadingModel: "Loading model…"
        case .running(let progress):
            switch progress.stage {
            case .preparing: "Preparing"
            case .encodingPrompt: "Encoding prompt"
            case .sampling: "Generating image"
            case .decoding: "Decoding image"
            case .other(let name): name
            }
        }
    }

    private var detail: String? {
        switch phase {
        case .loadingModel:
            "The first load can take a while."
        case .running(let progress):
            if case .sampling = progress.stage, progress.total > 0 {
                "Step \(min(progress.completed, progress.total)) of \(progress.total)"
            } else {
                nil
            }
        default:
            nil
        }
    }
}

/// A faint band of light sweeping across the placeholder.
private struct Shimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Theme.card
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let sweep = time.truncatingRemainder(dividingBy: 2.4) / 2.4
                GeometryReader { geometry in
                    let width = geometry.size.width
                    ZStack(alignment: .leading) {
                        Theme.card.opacity(0.6)
                        LinearGradient(
                            colors: [.clear, Theme.accent.opacity(0.10), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.6)
                        .offset(x: -width * 0.6 + sweep * width * 1.6)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Error

private struct ErrorCard: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 30, height: 30)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Generation failed")
                    .font(.callout.weight(.semibold))
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss") { model.dismissError() }
                .buttonStyle(SoftButtonStyle())
        }
        .card(padding: 12)
    }
}

// MARK: - Composer

private struct Composer: View {
    @Environment(AppModel.self) private var model
    @State private var showsAdvanced = false
    @FocusState private var promptFocused: Bool

    private static let sizePresets = [
        ImageSize(width: 512, height: 512), ImageSize(width: 768, height: 768),
        ImageSize(width: 1024, height: 1024), ImageSize(width: 1024, height: 1536),
        ImageSize(width: 1536, height: 1024),
    ]

    var body: some View {
        @Bindable var model = model
        let isBusy = model.phase.isBusy
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            TextField("Describe an image…", text: $model.draft.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(2...6)
                .focused($promptFocused)
                .onSubmit { model.generate() }
                .padding([.top, .horizontal], 16)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                sizeMenu
                Button { showsAdvanced.toggle() } label: {
                    RoundIcon(systemImage: "slider.horizontal.3", active: showsAdvanced)
                }
                .buttonStyle(.plain)
                .help("Advanced settings")
                .accessibilityLabel("Advanced settings")
                .popover(isPresented: $showsAdvanced, arrowEdge: .top) {
                    AdvancedSettings()
                        .environment(model)
                }

                Spacer(minLength: 8)

                SendButton(isBusy: isBusy) {
                    if isBusy { model.cancelGeneration() } else { model.generate() }
                }
                .disabled(!isBusy && !model.canGenerate)
            }
            .padding([.horizontal, .bottom], 10)
        }
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        .onAppear { promptFocused = true }
    }

    private var sizeMenu: some View {
        let current = ImageSize(width: model.draft.width, height: model.draft.height)
        let sizes = Self.sizePresets.contains(current) ? Self.sizePresets : Self.sizePresets + [current]
        return Menu {
            ForEach(sizes, id: \.self) { size in
                Button {
                    model.draft.width = size.width
                    model.draft.height = size.height
                } label: {
                    if size == current {
                        Label(size.title, systemImage: "checkmark")
                    } else {
                        Text(verbatim: size.title)
                    }
                }
            }
        } label: {
            RoundIcon(systemImage: "aspectratio")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Image size: \(current.title)")
        .accessibilityLabel("Image size")
        .accessibilityValue(current.title)
    }
}

private struct SendButton: View {
    let isBusy: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: isBusy ? "stop.fill" : "arrow.up")
                .font(.system(size: isBusy ? 10 : 13, weight: .bold))
                .foregroundStyle(isBusy ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(.white))
                .frame(width: 30, height: 30)
                .background(isBusy ? AnyShapeStyle(Color.primary.opacity(0.85)) : AnyShapeStyle(Theme.accent), in: Circle())
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .help(isBusy ? "Stop (⌘.)" : "Generate (⌘↩)")
        .accessibilityLabel(isBusy ? "Stop" : "Generate")
    }
}

private struct ImageSize: Hashable {
    let width: Int
    let height: Int

    var title: String { "\(width) × \(height)" }
}

// MARK: - Advanced settings

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Advanced Settings")
                    .font(.headline)
                Text(verbatim: model.selectedRecipe?.name ?? "No model selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            section("Negative prompt") {
                TextField("Things to keep out of the image", text: $model.draft.negativePrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
            }

            section("Sampling") {
                row("Steps") {
                    Text(verbatim: "\(model.draft.steps)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("Steps", value: $model.draft.steps, in: 1...150)
                        .labelsHidden()
                }
                Divider()
                row("CFG") {
                    Slider(value: $model.draft.cfg, in: 0...20, step: 0.5)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 130)
                    Text(verbatim: model.draft.cfg.formatted(.number.precision(.fractionLength(1))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                Divider()
                row("Sampler") {
                    Picker("Sampler", selection: $model.draft.sampler) {
                        ForEach(samplers, id: \.self) { sampler in
                            Text(verbatim: sampler).tag(sampler)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            section("Seed") {
                row("Random seed") {
                    Toggle("Random seed", isOn: $model.draft.randomSeed)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                if !model.draft.randomSeed {
                    Divider()
                    row("Seed") {
                        TextField("Seed", value: $model.draft.seed, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 150)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    model.selectRecipe(model.selectedRecipe)
                } label: {
                    Label("Reset to recommended", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(model.selectedRecipe == nil)

                if let note = model.selectedRecipe?.licenseNote, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 10, radius: 10)
        }
    }

    private func row(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 22)
    }

    private var samplers: [String] {
        let known = AppModel.samplers
        return known.contains(model.draft.sampler) ? known : known + [model.draft.sampler]
    }
}
