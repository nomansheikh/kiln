import SwiftUI

/// The prompt field with its size, settings and send controls.
/// Return sends the prompt; Option-Return adds a line.
struct PromptComposer: View {
    @Environment(AppModel.self) private var model
    @State private var showsAdvanced = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        @Bindable var generation = model.generation
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        VStack(alignment: .leading, spacing: 4) {
            TextField("Describe an image", text: $generation.draft.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...8)
                .focused($promptFocused)
                .onSubmit(send)
                .padding(.horizontal, 8)
                .padding(.top, 6)

            HStack(spacing: 6) {
                GenerationImageSizeMenu(draft: $generation.draft)
                advancedButton
                Spacer(minLength: 8)
                PromptSendButton(isBusy: generation.phase.isBusy, action: send)
                    .disabled(!generation.phase.isBusy && !generation.canGenerate)
            }
        }
        .padding(12)
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.07), radius: 18, y: 6)
        .contentShape(shape)
        .onTapGesture { promptFocused = true }
        .onAppear { promptFocused = true }
    }

    /// Sends the prompt, or stops the image being generated.
    private func send() {
        let generation = model.generation
        if generation.phase.isBusy {
            generation.cancel()
        } else {
            generation.generate()
        }
        promptFocused = true
    }

    private var advancedButton: some View {
        Button { showsAdvanced.toggle() } label: {
            ComposerChip(
                systemImage: "slider.horizontal.3",
                title: "\(model.generation.draft.steps) steps",
                active: showsAdvanced
            )
        }
        .buttonStyle(.plain)
        .help("Steps, guidance, sampler and seed")
        .accessibilityLabel("Advanced settings")
        .popover(isPresented: $showsAdvanced, arrowEdge: .top) {
            GenerationAdvancedSettings()
                .environment(model)
        }
    }
}

/// The round send button: an arrow, or a stop square while generating.
struct PromptSendButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isBusy ? "stop.fill" : "arrow.up")
                .font(.system(size: isBusy ? 11 : 14, weight: .bold))
                .foregroundStyle(Theme.window)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(isEnabled ? 1 : 0.25), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isBusy ? "Stop (\u{2318}.)" : "Generate (\u{21A9})")
        .accessibilityLabel(isBusy ? "Stop" : "Generate")
    }
}
