import SwiftUI

/// The composer's chip that shows the chosen voice and opens the voice list.
struct SpeechVoiceChip: View {
    @Environment(AppModel.self) private var model
    let voices: [String]
    @State private var showsVoices = false

    var body: some View {
        let speech = model.speech
        let current = speech.voice.flatMap { voices.contains($0) ? $0 : nil } ?? voices.first ?? ""

        Button { showsVoices.toggle() } label: {
            HStack(spacing: 6) {
                VoiceAvatar(name: current, size: 18)
                Text(verbatim: GenerationVoiceMenu.title(current))
                    .font(.callout)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(showsVoices ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .frame(height: 28)
            .background(Color.primary.opacity(showsVoices ? 0.1 : 0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .focusable(false)
        .help("Voice")
        .accessibilityLabel("Voice")
        .accessibilityValue(GenerationVoiceMenu.title(current))
        #if DEBUG
        .task {
            guard DebugSnapshot.opensVoiceList else { return }
            try? await Task.sleep(for: .milliseconds(700))
            showsVoices = true
        }
        #endif
        .popover(isPresented: $showsVoices, arrowEdge: .top) {
            SpeechVoiceList(voices: voices, current: current) { showsVoices = false }
                .environment(model)
                .focusRingsWhileNavigating()
        }
    }
}
