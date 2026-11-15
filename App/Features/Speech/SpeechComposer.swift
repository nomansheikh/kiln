import KilnCore
import SwiftUI

/// The Speech screen's text field with its voice chip, length and send
/// button, in the same shape as the Generate screen's composer. Return makes
/// the clip; Shift-Return adds a line.
struct SpeechComposer: View {
    @Environment(AppModel.self) private var model
    @State private var editor = SpeechEditorProxy()
    @State private var textHeight = SpeechTextEditor.height(ofLines: 3)
    @State private var isFocused = false

    var body: some View {
        @Bindable var speech = model.speech
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        VStack(alignment: .leading, spacing: 6) {
            SpeechTextEditor(text: $speech.text, tags: tags, showsSpeakers: speech.isScript, proxy: editor, height: $textHeight, isFocused: $isFocused, onSubmit: send)
                // Three lines tall when empty; a long text scrolls inside the field.
                .frame(height: min(max(textHeight, SpeechTextEditor.height(ofLines: 3)), SpeechTextEditor.height(ofLines: 12)))
                .overlay(alignment: .topLeading) {
                    if speech.text.isEmpty {
                        Text("Type or paste the text you want to hear, or a script such as \u{201C}Anna: Did you hear that?\u{201D}")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if let problem = speech.voiceProblem {
                HStack(spacing: 8) {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(speech.savedVoice == nil ? "Add a voice\u{2026}" : "Add the words\u{2026}") {
                        if let voice = speech.savedVoice {
                            speech.edit(voice)
                        } else {
                            speech.editedVoiceID = nil
                            speech.isAddingVoice = true
                        }
                    }
                    .buttonStyle(SoftButtonStyle())
                    .controlSize(.small)
                }
                .padding(.horizontal, 8)
            }

            if let problem = speech.speakerProblem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
            }

            if let skipped {
                Text(skipped)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                if speech.isScript {
                    SpeechSpeakersChip(editor: editor)
                } else if let recipe = speech.selectedRecipe, !recipe.voices.isEmpty || speech.copiesVoices {
                    SpeechVoiceChip(voices: recipe.voices)
                }
                if let languages = speech.selectedRecipe?.languages, languages.count > 1 {
                    GenerationLanguageMenu(languages: languages, selection: $speech.language)
                }
                if let groups = speech.selectedRecipe?.speech?.styles {
                    SpeechStyleMenu(groups: groups, chosen: $speech.styleWords)
                } else if let kind = speech.selectedRecipe?.speech?.instruction {
                    SpeechStyleChip(kind: kind)
                }
                if !tags.isEmpty {
                    SpeechTagMenu(tags: tags, text: $speech.text, editor: editor)
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
        .composerGlow(isWorking: speech.isGenerating, isFocused: isFocused)
        .shadow(color: .black.opacity(0.07), radius: 18, y: 6)
        .contentShape(shape)
        .onTapGesture { editor.focus() }
        .animation(.snappy(duration: 0.2), value: speech.text.isEmpty)
        .task {
            // Typing should work straight away, as on the Generate screen. Text left
            // from before is not focused: focusing selects it all, and the next key
            // would replace it.
            guard model.speech.text.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(150))
            editor.focus()
        }
    }

    /// The selected model's own marks for sounds.
    private var tags: [String] {
        model.speech.selectedRecipe?.speech?.tags ?? []
    }

    /// A line naming the marks in the text that the selected model has no sound for.
    private var skipped: String? {
        let speech = model.speech
        guard speech.selectedRecipe != nil else { return nil }
        var names: [String] = []
        for mark in SpeechMarks.marks(in: speech.text, tags: tags) where mark.tag == nil && !names.contains(mark.written) {
            names.append(mark.written)
        }
        guard !names.isEmpty else { return nil }
        let list = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " and others" : "")
        return tags.isEmpty
            ? "This model makes no sounds, so \(list) will be left out."
            : "This model has no sound for \(list), so it will be left out."
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
        if let problem = speech.voiceProblem ?? speech.speakerProblem { return problem }
        if speech.needsInstruction { return "This model needs a description of the voice. Add one under Style." }
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
        editor.focus()
    }
}
