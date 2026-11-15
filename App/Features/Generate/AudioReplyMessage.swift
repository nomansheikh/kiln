import AppKit
import KilnCore
import SwiftUI

/// Sound a model made, such as speech: a small player with its row of quiet actions.
struct AudioReplyMessage: View {
    @Environment(AppModel.self) private var model
    let item: AudioItem
    let regenerate: () -> Void
    @State private var playback: AudioPlayback

    init(item: AudioItem, regenerate: @escaping () -> Void) {
        self.item = item
        self.regenerate = regenerate
        _playback = State(initialValue: AudioPlayback(url: item.url, duration: item.durationSeconds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            player
            HStack(spacing: 2) {
                MessageActionButton(systemImage: "arrow.down.to.line", help: "Save As…") {
                    GenerationResultExporter.saveCopy(of: item)
                }
                ShareLink(item: item.url) {
                    MessageActionIcon(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PressableButtonStyle())
                .help("Share")
                MessageActionButton(systemImage: "folder", help: "Show in Finder") {
                    model.audio.revealInFinder(item)
                }
                MessageActionButton(systemImage: "arrow.clockwise", help: "Generate again", bounces: true) {
                    regenerate()
                }
                .disabled(model.generation.phase.isBusy)
            }
        }
        .onDisappear { playback.pause() }
    }

    private var player: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return HStack(spacing: 12) {
            Button { playback.toggle() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Theme.window)
                    .frame(width: 36, height: 36)
                    .background(Color.primary, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .help(playback.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Slider(
                value: Binding(get: { playback.position }, set: { playback.seek(to: $0) }),
                in: 0...max(playback.duration, 0.1)
            )
            .controlSize(.small)
            .tint(Theme.accent)
            .accessibilityLabel("Position")

            Text("\(Self.clock(playback.position)) / \(Self.clock(playback.duration))")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(width: 420, height: 56)
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(Theme.hairline))
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Generated audio: \(item.record.request.prompt)")
    }

    /// Minutes and seconds, such as "0:47".
    private static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.down))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }
}
