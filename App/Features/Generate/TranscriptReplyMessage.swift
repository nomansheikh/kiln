import AppKit
import KilnCore
import SwiftUI

/// What was said in a recording, as rows that each start at a time. Clicking a row
/// plays the recording from there.
struct TranscriptReplyMessage: View {
    @Environment(AppModel.self) private var model
    let transcript: Transcript
    /// The recording the transcript was made from, when it is still on this Mac.
    let recording: URL?
    let regenerate: () -> Void

    @State private var playback: AudioPlayback?
    /// Shows the words as one paragraph, for reading or selecting across segments.
    @State private var asParagraph = false

    var body: some View {
        TranscriptCard(title: name, subtitle: subtitle, fraction: fraction) {
            playButton
        } rows: {
            if transcript.isEmpty {
                words("No speech was found in the audio.").foregroundStyle(.secondary)
            } else if asParagraph || !transcript.hasTimes {
                words(transcript.text).textSelection(.enabled)
            } else {
                TranscriptRows(
                    transcript: transcript,
                    current: playback?.isPlaying == true ? transcript.segmentIndex(at: playback?.position ?? 0) : nil,
                    play: playback.map { playback in
                        { segment in
                            playback.seek(to: segment.start)
                            playback.play()
                        }
                    }
                )
            }
        } footer: {
            TranscriptActions(transcript: transcript, name: baseName, asParagraph: $asParagraph, regenerate: regenerate)
        }
        .onAppear {
            guard playback == nil, let recording, FileManager.default.fileExists(atPath: recording.path) else { return }
            playback = AudioPlayback(url: recording, duration: transcript.duration)
        }
        .onDisappear { playback?.pause() }
    }

    private func words(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var playButton: some View {
        if let playback {
            Button {
                playback.toggle()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableButtonStyle())
            .hint(playback.isPlaying ? "Pause" : "Play the recording")
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.12), in: Circle())
        }
    }

    private var fraction: Double {
        guard let playback, playback.duration > 0 else { return 0 }
        return playback.position / playback.duration
    }

    private var name: String {
        recording.map(AttachmentLibrary.displayName(of:)) ?? "Transcript"
    }

    /// The recording's name without its ending, for the file a transcript is saved as.
    private var baseName: String {
        (name as NSString).deletingPathExtension
    }

    private var subtitle: String {
        guard !transcript.isEmpty else { return "Transcript" }
        let length = Transcript.clock(max(playback?.duration ?? 0, transcript.duration))
        if let playback, playback.isPlaying || playback.position > 0 {
            return "\(Transcript.clock(playback.position)) of \(length)"
        }
        let words = transcript.text.split(whereSeparator: \.isWhitespace).count
        return "\(length) · \(words) \(words == 1 ? "word" : "words")"
    }
}
