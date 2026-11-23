import KilnCore
import SwiftUI

/// The popover with the settings most people leave alone: sampling, how the
/// object is cut out of its picture, the size of its colours, and the seed.
struct ObjectsAdvancedSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var studio = model.studio
        let draft = studio.draft

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Advanced Settings")
                    .font(.headline)
                Text(verbatim: studio.selectedRecipe?.name ?? "No model selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            section("Sampling") {
                row("Steps", help: "More steps are slower and, up to a point, cleaner.") {
                    Text(verbatim: "\(draft.steps)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("Steps", value: $studio.draft.steps, in: MeshSettings.stepsRange)
                        .labelsHidden()
                }
                Divider()
                guidance("Form", value: $studio.draft.structureGuidance, help: "How closely the overall form follows the picture.")
                Divider()
                guidance("Surface", value: $studio.draft.shapeGuidance, help: "How closely the surface follows the picture.")
            }

            section("Picture") {
                row("Cut out", help: "How the object is separated from its background.") {
                    Picker("Cut out", selection: $studio.draft.cutout) {
                        ForEach(MeshSettings.Cutout.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                row("Colour size", help: "Side of the object's colour image. Larger is sharper and makes a bigger file.") {
                    Picker("Colour size", selection: $studio.draft.textureSize) {
                        Text("Automatic").tag(Int?.none)
                        ForEach(MeshSettings.textureSizes, id: \.self) { size in
                            Text(verbatim: "\(size) px").tag(Int?.some(size))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            section("Seed") {
                row("Random seed", help: "A new seed each time gives a different object from the same picture.") {
                    Toggle("Random seed", isOn: $studio.draft.randomSeed)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                if !draft.randomSeed {
                    Divider()
                    row("Seed", help: "The same seed, picture and settings give the same object.") {
                        TextField("Seed", value: $studio.draft.seed, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 150)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Reset to Defaults") { studio.draft.resetAdvanced() }
                    .buttonStyle(SoftButtonStyle())
                    .controlSize(.small)
                    .disabled(!draft.hasCustomSettings)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func guidance(_ title: String, value: Binding<Double>, help: String) -> some View {
        row(title, help: help) {
            Slider(value: value, in: MeshSettings.guidanceRange, step: 0.5)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 130)
            Text(verbatim: value.wrappedValue.formatted(.number.precision(.fractionLength(1))))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 8) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 10, radius: 10)
        }
    }

    private func row(_ title: String, help: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            content()
        }
        .help(help)
    }
}
