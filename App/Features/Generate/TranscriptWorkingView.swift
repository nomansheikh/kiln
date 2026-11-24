import KilnCore
import SwiftUI

/// A transcript while it is being written: the rows so far, in the card the finished one will have.
struct TranscriptWorkingView: View {
    let phase: GenerationPhase
    /// What has been written down so far.
    let transcript: Transcript
    let recording: URL?

    var body: some View {
        TranscriptCard(
            title: recording.map(AttachmentLibrary.displayName(of:)) ?? "Recording",
            subtitle: subtitle,
            fraction: phase.progressFraction ?? 0
        ) {
            WaveformBars()
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.12), in: Circle())
        } rows: {
            if transcript.isEmpty {
                ShimmeringText(text: phase.progressDetail ?? "Listening to the recording")
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TranscriptRows(transcript: transcript)
            }
        } footer: {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(phase.progressTitle)
    }

    private var subtitle: String {
        guard let fraction = phase.progressFraction else { return phase.progressTitle }
        return "\(phase.progressTitle) · \(Int((fraction * 100).rounded()))%"
    }
}
