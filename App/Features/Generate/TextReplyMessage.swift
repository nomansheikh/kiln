import AppKit
import SwiftUI

/// Text a model wrote, such as a transcript, with its row of quiet actions.
struct TextReplyMessage: View {
    @Environment(AppModel.self) private var model
    let text: String
    let regenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.isEmpty ? "No speech was found in the audio." : text)
                .font(.system(size: 15))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)

            HStack(spacing: 2) {
                MessageActionButton(systemImage: "doc.on.doc", help: "Copy text", confirms: true) {
                    NSPasteboard.general.copyText(text)
                }
                .disabled(text.isEmpty)
                ShareLink(item: text) {
                    MessageActionIcon(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PressableButtonStyle())
                .help("Share")
                .disabled(text.isEmpty)
                MessageActionButton(systemImage: "arrow.clockwise", help: "Run again", bounces: true) {
                    regenerate()
                }
                .disabled(model.generation.phase.isBusy)
            }
            // Line the first icon up with the text above it.
            .padding(.leading, -8)
        }
    }
}
