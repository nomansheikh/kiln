import SwiftUI

/// The popover with the settings most people leave alone: negative prompt, sampling and seed.
struct GenerationAdvancedSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            negativePromptSection
            samplingSection
            seedSection
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Advanced Settings")
                .font(.headline)
            Text(verbatim: model.generation.selectedRecipe?.name ?? "No model selected")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var negativePromptSection: some View {
        @Bindable var generation = model.generation
        return section("Negative prompt") {
            TextField("Things to keep out of the image", text: $generation.draft.negativePrompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
        }
    }

    private var samplingSection: some View {
        @Bindable var generation = model.generation
        let draft = generation.draft
        return section("Sampling") {
            row("Steps") {
                Text(verbatim: "\(draft.steps)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper("Steps", value: $generation.draft.steps, in: 1...150)
                    .labelsHidden()
            }
            Divider()
            row("CFG") {
                Slider(value: $generation.draft.cfg, in: 0...20, step: 0.5)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 130)
                Text(verbatim: draft.cfg.formatted(.number.precision(.fractionLength(1))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            Divider()
            row("Sampler") {
                Picker("Sampler", selection: $generation.draft.sampler) {
                    ForEach(samplers, id: \.self) { sampler in
                        Text(verbatim: sampler).tag(sampler)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var seedSection: some View {
        @Bindable var generation = model.generation
        return section("Seed") {
            row("Random seed") {
                Toggle("Random seed", isOn: $generation.draft.randomSeed)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if !generation.draft.randomSeed {
                Divider()
                row("Seed") {
                    TextField("Seed", value: $generation.draft.seed, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 150)
                }
            }
        }
    }

    private var footer: some View {
        let generation = model.generation
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                generation.selectRecipe(generation.selectedRecipe)
            } label: {
                Label("Reset to recommended", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(generation.selectedRecipe == nil)

            if let note = generation.selectedRecipe?.licenseNote, !note.isEmpty {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Building blocks

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

    /// The known samplers, plus the draft's own when a recipe names one Kiln does not list.
    private var samplers: [String] {
        let known = GenerationStore.samplers
        let current = model.generation.draft.sampler
        return known.contains(current) ? known : known + [current]
    }
}
