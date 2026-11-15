import KilnCore
import SwiftUI

/// The speakers of the script in the composer, each with the voice it is read in.
struct SpeechSpeakerList: View {
    @Environment(AppModel.self) private var model
    let editor: SpeechEditorProxy
    let dismiss: () -> Void

    var body: some View {
        let speech = model.speech
        let speakers = speech.script.speakers
        let most = speech.speakerRule?.max

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Speakers")
                    .font(.headline)
                Text("Start a line with a name and a colon, such as \u{201C}Anna: Hello.\u{201D} Add how it is said in brackets: \u{201C}Anna (whispering): Hello.\u{201D}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(speakers.enumerated()), id: \.element) { index, speaker in
                    HStack(spacing: 10) {
                        VoiceAvatar(name: speaker, size: 30, tint: VoiceAvatar.hue(ofSpeaker: index))
                        Text(verbatim: speaker)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        SpeechSpeakerVoiceMenu(speaker: speaker, dismiss: dismiss)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                }
                Button {
                    dismiss()
                    editor.startLine(for: speech.nextSpeakerName)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Theme.card, in: Circle())
                        Text("Add a speaker")
                            .font(.callout.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(most.map { speakers.count >= $0 } ?? false)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: 340)
    }
}
