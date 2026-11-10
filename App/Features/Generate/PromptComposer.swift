import SwiftUI
import UniformTypeIdentifiers

/// The prompt field with its attachment, size, settings and send controls.
/// Return sends the prompt; Option-Return adds a line. An image can be
/// attached with the plus button or by dropping a file on the composer.
struct PromptComposer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAdvanced = false
    @State private var isPickingImage = false
    @State private var isDropTarget = false
    @State private var attachError: String?
    @FocusState private var promptFocused: Bool

    var body: some View {
        @Bindable var generation = model.generation
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let attachment = generation.draft.attachment

        VStack(alignment: .leading, spacing: 6) {
            if let attachment {
                ComposerAttachment(url: attachment, strength: $generation.draft.editStrength) {
                    generation.removeAttachment()
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .topLeading)))
            }

            TextField(attachment == nil ? "Describe an image" : "Describe how to change it", text: $generation.draft.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                // Two lines tall when empty, so there is visible room to write.
                .lineLimit(2...8)
                .focused($promptFocused)
                .onSubmit(send)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)

            HStack(spacing: 6) {
                attachButton
                GenerationImageSizeMenu(draft: $generation.draft)
                advancedButton
                Spacer(minLength: 8)
                PromptSendButton(isBusy: generation.phase.isBusy, action: send)
                    .disabled(!generation.phase.isBusy && !generation.canGenerate)
            }
        }
        .padding(12)
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(isDropTarget ? Theme.accent : Theme.hairline, lineWidth: isDropTarget ? 2 : 1))
        .shadow(color: .black.opacity(0.07), radius: 18, y: 6)
        .contentShape(shape)
        .onTapGesture { promptFocused = true }
        .task {
            // Typing should work straight away. The short wait lets the window
            // finish choosing its own first control, which would otherwise win.
            try? await Task.sleep(for: .milliseconds(150))
            promptFocused = true
        }
        .animation(Motion.layout(reduced: reduceMotion), value: attachment)
        .dropDestination(for: URL.self) { urls, _ in
            guard let file = urls.first else { return false }
            attach(file)
            return true
        } isTargeted: { isDropTarget = $0 }
        .fileImporter(isPresented: $isPickingImage, allowedContentTypes: [.image]) { result in
            if case .success(let file) = result { attach(file) }
        }
        .alert("Could Not Attach Image", isPresented: Binding(isPresenting: $attachError)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachError ?? "")
        }
    }

    // MARK: - Actions

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

    private func attach(_ file: URL) {
        do {
            try model.generation.attach(file)
            promptFocused = true
        } catch {
            attachError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Controls

    private var attachButton: some View {
        Button { isPickingImage = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .focusable(false)
        .help("Attach an image to edit")
        .accessibilityLabel("Attach image")
    }

    private var advancedButton: some View {
        Button { showsAdvanced.toggle() } label: {
            ComposerChip(
                systemImage: "slider.horizontal.3",
                title: "\(model.generation.draft.steps) steps",
                active: showsAdvanced
            )
        }
        .buttonStyle(PressableButtonStyle())
        .focusable(false)
        .help("Steps, guidance, sampler and seed")
        .accessibilityLabel("Advanced settings")
        .popover(isPresented: $showsAdvanced, arrowEdge: .top) {
            GenerationAdvancedSettings()
                .environment(model)
                .focusRingsWhileNavigating()
        }
    }
}
