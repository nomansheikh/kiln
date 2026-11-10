import SwiftUI

/// The rounded prompt field with its size, advanced-settings and send controls.
struct PromptComposer: View {
    @Environment(AppModel.self) private var model
    @State private var showsAdvanced = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        @Bindable var generation = model.generation
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            TextField("Describe an image…", text: $generation.draft.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(2...6)
                .focused($promptFocused)
                .onSubmit { generation.generate() }
                .padding([.top, .horizontal], 16)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                GenerationImageSizeMenu(draft: $generation.draft)
                advancedButton

                Spacer(minLength: 8)

                sendButton
            }
            .padding([.horizontal, .bottom], 10)
        }
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        .onAppear { promptFocused = true }
    }

    // MARK: - Controls

    private var advancedButton: some View {
        Button { showsAdvanced.toggle() } label: {
            GenerateRoundIcon(systemImage: "slider.horizontal.3", active: showsAdvanced)
        }
        .buttonStyle(.plain)
        .help("Advanced settings")
        .accessibilityLabel("Advanced settings")
        .popover(isPresented: $showsAdvanced, arrowEdge: .top) {
            GenerationAdvancedSettings()
                .environment(model)
        }
    }

    private var sendButton: some View {
        let generation = model.generation
        let isBusy = generation.phase.isBusy
        return GenerateSendButton(isBusy: isBusy) {
            if isBusy { generation.cancel() } else { generation.generate() }
        }
        .disabled(!isBusy && !generation.canGenerate)
    }
}
