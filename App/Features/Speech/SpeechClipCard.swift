import KilnCore
import SwiftUI

/// One clip: a play button, who said it, its waveform to scrub through, the
/// text it was made from, and what can be done with the file.
struct SpeechClipCard: View {
    @Environment(AppModel.self) private var model
    let clip: AudioItem
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        let speech = model.speech
        let isCurrent = speech.current?.id == clip.id
        let playback = isCurrent ? speech.playback : nil
        let isPlaying = playback?.isPlaying == true
        let position = playback?.position ?? 0
        let duration = max(playback?.duration ?? clip.durationSeconds, 0.01)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { speech.togglePlayback(of: clip) } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .frame(width: 36, height: 36)
                        .background(isCurrent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.cardHover), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.9))
                .help(isPlaying ? "Pause" : "Play")
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                if let name = clip.record.request.speech?.reference?.name {
                    VoiceAvatar(name: name, size: 22)
                    Text(verbatim: name)
                        .font(.callout.weight(.semibold))
                } else if let voice = clip.record.request.speech?.voice {
                    VoiceAvatar(name: voice, size: 22)
                    Text(verbatim: GenerationVoiceMenu.title(voice))
                        .font(.callout.weight(.semibold))
                }
                Text(verbatim: detail)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                actions
                    .opacity(hovering || isCurrent ? 1 : 0)
            }

            HStack(spacing: 12) {
                WaveformView(peaks: speech.peaks[clip.id] ?? [], progress: position / duration) { fraction in
                    speech.seek(clip, to: fraction)
                }
                .frame(height: 40)
                Text(isCurrent ? "\(Self.clock(position)) / \(Self.clock(duration))" : Self.clock(duration))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Text(verbatim: clip.record.request.prompt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 14, radius: 18)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
        .animation(.snappy(duration: 0.2), value: isCurrent)
        .task(id: clip.id) { await speech.loadPeaks(for: clip) }
        .onDrag { NSItemProvider(contentsOf: clip.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Use This Text", systemImage: "square.and.pencil") { speech.reuse(clip) }
            Button("Show in Finder", systemImage: "folder") { model.audio.revealInFinder(clip) }
            Button("Save As…", systemImage: "arrow.down.to.line") { GenerationResultExporter.saveCopy(of: clip) }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive, action: delete)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clip: \(clip.record.request.prompt)")
    }

    private var actions: some View {
        HStack(spacing: 0) {
            MessageActionButton(systemImage: "square.and.pencil", help: "Use this text again") {
                model.speech.reuse(clip)
            }
            MessageActionButton(systemImage: "folder", help: "Show in Finder") {
                model.audio.revealInFinder(clip)
            }
            ShareLink(item: clip.url) { MessageActionIcon(systemImage: "square.and.arrow.up") }
                .buttonStyle(PressableButtonStyle())
                .help("Share")
            MessageActionButton(systemImage: "arrow.down.to.line", help: "Save As…") {
                GenerationResultExporter.saveCopy(of: clip)
            }
            MessageActionButton(systemImage: "trash", help: "Delete", action: delete)
        }
        // Line the last icon up with the card's edge.
        .padding(.trailing, -6)
    }

    /// The model and the clip's age, such as "PocketTTS English · 2 min ago".
    private var detail: String {
        [clip.record.recipeName, clip.record.createdAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))]
            .joined(separator: " \u{00B7} ")
    }

    /// Minutes and seconds, such as "0:47".
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds).rounded(.down))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }
}
