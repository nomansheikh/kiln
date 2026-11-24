import AppKit
import KilnCore
import SwiftUI

/// The line of quiet actions under a transcript.
struct TranscriptActions: View {
    @Environment(AppModel.self) private var model
    let transcript: Transcript
    /// Name of the file a saved transcript gets, without an ending.
    let name: String
    @Binding var asParagraph: Bool
    let regenerate: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            MessageActionButton(systemImage: "doc.on.doc", help: "Copy text", confirms: true) {
                NSPasteboard.general.copyText(transcript.text)
            }
            .disabled(transcript.isEmpty)
            if transcript.hasTimes {
                MessageActionButton(
                    systemImage: asParagraph ? "list.bullet" : "text.alignleft",
                    help: asParagraph ? "Show times" : "Show as one paragraph"
                ) {
                    asParagraph.toggle()
                }
            }
            Menu {
                Button("Text (.txt)") { TranscriptExporter.save(transcript, as: nil, named: name) }
                if transcript.hasTimes {
                    ForEach(Transcript.SubtitleFormat.allCases, id: \.self) { format in
                        Button("Subtitles, \(format.name)") { TranscriptExporter.save(transcript, as: format, named: name) }
                    }
                }
            } label: {
                MessageActionIcon(systemImage: "square.and.arrow.down")
            }
            .menuStyle(.button)
            .buttonStyle(PressableButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .hint("Save as a file")
            .disabled(transcript.isEmpty)
            Spacer(minLength: 0)
            MessageActionButton(systemImage: "arrow.clockwise", help: "Run again", bounces: true) {
                regenerate()
            }
            .disabled(model.generation.phase.isBusy)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
