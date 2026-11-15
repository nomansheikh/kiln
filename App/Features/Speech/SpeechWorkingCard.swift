import SwiftUI

/// Stands in for a clip while it is being made: what the model is doing,
/// over a waveform that ripples until the real one arrives.
struct SpeechWorkingCard: View {
    let title: String
    let voice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
                if let voice {
                    VoiceAvatar(name: voice, size: 22)
                    Text(verbatim: GenerationVoiceMenu.title(voice))
                        .font(.callout.weight(.semibold))
                }
                ShimmeringText(text: title)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            WaveformView(peaks: [], progress: 0, isWorking: true) { _ in }
                .frame(height: 40)
                .disabled(true)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
