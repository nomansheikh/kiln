import KilnCore
import SwiftUI

/// The composer's chip for a script: it shows how many speakers the text has
/// and opens the list where each is given a voice.
struct SpeechSpeakersChip: View {
    @Environment(AppModel.self) private var model
    let editor: SpeechEditorProxy
    @State private var showsSpeakers = false

    var body: some View {
        let speakers = model.speech.script.speakers
        let title = speakers.count > 1 ? "\(speakers.count) speakers" : "Speakers"

        Button { showsSpeakers.toggle() } label: {
            HStack(spacing: 6) {
                HStack(spacing: -6) {
                    let shown = speakers.isEmpty ? [SpeechScript.unnamedSpeaker] : Array(speakers.prefix(4))
                    ForEach(Array(shown.enumerated()), id: \.element) { index, speaker in
                        VoiceAvatar(name: speaker, size: 18, tint: VoiceAvatar.hue(ofSpeaker: index))
                            .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 1))
                    }
                }
                Text(verbatim: title)
                    .font(.callout)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(showsSpeakers ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .frame(height: 28)
            .background(Color.primary.opacity(showsSpeakers ? 0.1 : 0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .focusable(false)
        .help("Speakers and their voices")
        .accessibilityLabel("Speakers")
        .accessibilityValue(title)
        #if DEBUG
        .task {
            guard DebugSnapshot.opensVoiceList else { return }
            try? await Task.sleep(for: .milliseconds(700))
            showsSpeakers = true
        }
        #endif
        .popover(isPresented: $showsSpeakers, arrowEdge: .top) {
            SpeechSpeakerList(editor: editor) { showsSpeakers = false }
                .environment(model)
                .focusRingsWhileNavigating()
        }
    }
}
