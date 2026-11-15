import KilnCore
import SwiftUI

/// The menu that gives one speaker of a script a voice: one of the model's,
/// one of the user's own, or a new one.
struct SpeechSpeakerVoiceMenu: View {
    @Environment(AppModel.self) private var model
    let speaker: String
    let dismiss: () -> Void

    var body: some View {
        let speech = model.speech
        let named = speech.selectedRecipe?.voices ?? []
        let current = speech.castVoice(of: speaker)
        // A model that reads scripts makes up a voice for a speaker without one;
        // any other would make up a new one for every line.
        let readsScripts = speech.speakerRule != nil

        Menu {
            if named.isEmpty, readsScripts {
                item("Model's own voice", isChosen: current == nil) { speech.choose(nil, for: speaker) }
            }
            ForEach(named, id: \.self) { voice in
                item(GenerationVoiceMenu.title(voice), isChosen: current?.voice == voice) {
                    speech.choose(.named(voice), for: speaker)
                }
            }
            if speech.copiesVoices {
                if !speech.voices.voices.isEmpty {
                    Section("My voices") {
                        ForEach(speech.voices.voices) { voice in
                            item(voice.name, isChosen: current?.reference?.name == voice.name) {
                                speech.choose(.saved(voice.id), for: speaker)
                            }
                        }
                    }
                }
                Divider()
                Button("Add a voice\u{2026}") {
                    dismiss()
                    speech.addVoice(for: speaker, designing: false)
                }
                Button("Design a voice\u{2026}") {
                    dismiss()
                    speech.addVoice(for: speaker, designing: true)
                }
            }
        } label: {
            ComposerChip(systemImage: "waveform", title: String(title(of: current, readsScripts: readsScripts).prefix(22)),
                         active: current == nil && !readsScripts)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointerCursor()
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .accessibilityLabel("Voice of \(speaker)")
    }

    private func title(of voice: CastVoice?, readsScripts: Bool) -> String {
        if let name = voice?.reference?.name { return name }
        if let named = voice?.voice { return GenerationVoiceMenu.title(named) }
        return readsScripts ? "Model's own voice" : "Choose a voice"
    }

    private func item(_ title: String, isChosen: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            if isChosen {
                Label(title, systemImage: "checkmark")
            } else {
                Text(verbatim: title)
            }
        }
    }
}
