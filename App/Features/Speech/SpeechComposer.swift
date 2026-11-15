import SwiftUI

/// The Speech screen's text field with its voice chip, length and send
/// button, in the same shape as the Generate screen's composer. Return makes
/// the clip; Option-Return adds a line.
struct SpeechComposer: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var speech = model.speech
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        VStack(alignment: .leading, spacing: 6) {
            TextField("Type or paste the text you want to hear", text: $speech.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineSpacing(3)
                // Three lines tall when empty; a long text scrolls inside the field.
                .lineLimit(3...12)
                .focused($focused)
                .onSubmit(send)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)

            HStack(spacing: 8) {
                if let recipe = speech.selectedRecipe, !recipe.voices.isEmpty {
                    SpeechVoiceChip(voices: recipe.voices)
                }
                SpeechRateMenu()
                Spacer(minLength: 8)
                if !speech.text.isEmpty {
                    Text(length)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
                PromptSendButton(isBusy: speech.isGenerating, action: send)
                    .disabled(!speech.isGenerating && !speech.canGenerate)
                    .help(sendHelp)
            }
        }
        .padding(12)
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.07), radius: 18, y: 6)
        .contentShape(shape)
        .onTapGesture { focused = true }
        .animation(.snappy(duration: 0.2), value: speech.text.isEmpty)
        .task {
            // Typing should work straight away, as on the Generate screen. Text left
            // from before is not focused: focusing selects it all, and the next key
            // would replace it.
            guard model.speech.text.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(150))
            focused = true
        }
    }

    /// The text's size and about how long it takes to say, such as "409 characters · about 0:26".
    private var length: String {
        let speech = model.speech
        let count = speech.text.count
        let characters = count == 1 ? "1 character" : "\(count.formatted()) characters"
        guard speech.estimatedSeconds >= 1 else { return characters }
        return "\(characters) \u{00B7} about \(SpeechClipCard.clock(speech.estimatedSeconds))"
    }

    private var sendHelp: String {
        let speech = model.speech
        if speech.isGenerating { return "Stop (\u{2318}.)" }
        if speech.canGenerate { return "Read it aloud (\u{21A9})" }
        if speech.preparingPreview != nil || speech.isEngineBusyElsewhere() {
            return "Another model is working. Wait for it to finish."
        }
        return "Type something first"
    }

    /// Makes the clip, or stops the one being made.
    private func send() {
        let speech = model.speech
        if speech.isGenerating {
            speech.cancel()
        } else {
            speech.generate()
        }
        focused = true
    }
}
