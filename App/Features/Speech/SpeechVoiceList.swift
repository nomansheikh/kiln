import SwiftUI

/// The voices of the selected model, each with a button to hear it first.
struct SpeechVoiceList: View {
    @Environment(AppModel.self) private var model
    let voices: [String]
    let current: String
    let dismiss: () -> Void

    var body: some View {
        let speech = model.speech
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice")
                    .font(.headline)
                Text(voices.isEmpty
                    ? "This model can speak in a voice it copies from a recording."
                    : "Press play to hear a voice before you choose it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(voices, id: \.self) { voice in
                        SpeechVoiceRow(voice: voice, isSelected: speech.savedVoice == nil && voice == current) {
                            speech.voice = voice
                            speech.savedVoiceID = nil
                            dismiss()
                        }
                    }
                    if speech.copiesVoices {
                        SpeechSavedVoices(hasModelVoices: !voices.isEmpty, dismiss: dismiss)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 380)
        }
        .frame(width: 300)
        .onDisappear { model.speech.previewPlayback?.pause() }
    }
}

/// One voice: choose it by clicking the row, or hear it with the button.
private struct SpeechVoiceRow: View {
    @Environment(AppModel.self) private var model
    let voice: String
    let isSelected: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        let speech = model.speech
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let isPreparing = speech.preparingPreview == voice
        let isPlaying = speech.isPreviewPlaying(voice)

        HStack(spacing: 10) {
            Button(action: choose) {
                HStack(spacing: 10) {
                    VoiceAvatar(name: voice, size: 30)
                    Text(verbatim: GenerationVoiceMenu.title(voice))
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .accessibilityLabel(GenerationVoiceMenu.title(voice))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button { speech.togglePreview(of: voice) } label: {
                ZStack {
                    if isPreparing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(isPlaying ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    }
                }
                .frame(width: 26, height: 26)
                .background(Theme.card, in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.9))
            .disabled(isPreparing)
            .help(isPlaying ? "Pause the sample" : "Hear this voice")
            .accessibilityLabel(isPlaying ? "Pause the sample" : "Hear \(GenerationVoiceMenu.title(voice))")
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(isSelected ? Theme.accent.opacity(0.11) : (hovering ? Theme.card : .clear), in: shape)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
    }
}
