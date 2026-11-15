import KilnCore
import SwiftUI

/// The composer's chip for describing the voice or the delivery, shown for a
/// model that takes such a description. It opens a small editor.
struct SpeechStyleChip: View {
    @Environment(AppModel.self) private var model
    /// Whether the model can speak without a description.
    let kind: ModelRecipe.Instruction
    @State private var showsEditor = false

    var body: some View {
        let written = model.speech.instruction.trimmingCharacters(in: .whitespacesAndNewlines)

        Button { showsEditor.toggle() } label: {
            ComposerChip(systemImage: "theatermasks", title: Self.title(written), active: !written.isEmpty || showsEditor)
        }
        .buttonStyle(PressableButtonStyle())
        .focusable(false)
        .help(written.isEmpty ? "Describe the voice or how to say it" : written)
        .accessibilityLabel("Style")
        .accessibilityValue(written.isEmpty ? "None" : written)
        #if DEBUG
        .task {
            guard DebugSnapshot.opensStyleEditor else { return }
            try? await Task.sleep(for: .milliseconds(700))
            showsEditor = true
        }
        #endif
        .popover(isPresented: $showsEditor, arrowEdge: .top) {
            SpeechStyleEditor(kind: kind) { showsEditor = false }
                .environment(model)
                .focusRingsWhileNavigating()
        }
    }

    /// The chip's text: the description, cut short so the chip stays a chip.
    private static func title(_ written: String) -> String {
        guard !written.isEmpty else { return "Style" }
        let line = written.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > 24 ? line.prefix(23).trimmingCharacters(in: .whitespaces) + "\u{2026}" : line
    }
}

/// The editor the style chip opens: one field, kept until it is cleared.
private struct SpeechStyleEditor: View {
    @Environment(AppModel.self) private var model
    let kind: ModelRecipe.Instruction
    let dismiss: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var speech = model.speech

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Style")
                    .font(.headline)
                Text(kind == .required
                    ? "This model needs a description of the voice before it can speak."
                    : "Describe the voice or how to say it. What a model follows differs from one to the next.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("For example: Very happy.", text: $speech.instruction, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(2...5)
                .focused($focused)
                .onSubmit(dismiss)
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Button("Clear") { speech.instruction = "" }
                    .buttonStyle(SoftButtonStyle())
                    .controlSize(.small)
                    .disabled(speech.instruction.isEmpty)
                Spacer()
                Button("Done", action: dismiss)
                    .buttonStyle(AccentButtonStyle())
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { focused = true }
    }
}
