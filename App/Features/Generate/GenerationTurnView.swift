import KilnCore
import SwiftUI

/// One exchange: the prompt on the right, the reply on the left.
struct GenerationTurnView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let turn: GenerationTurn
    /// Progress of the running generation, used when this turn is the one running.
    let phase: GenerationPhase
    let preview: GeneratedImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .trailing, spacing: 8) {
                if let attachment = turn.attachment {
                    if AttachmentLibrary.kind(of: attachment) == .image {
                        Thumbnail(url: attachment, maxPixelSize: 320)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
                            .accessibilityLabel("Attached image")
                    } else {
                        AttachmentChip(url: attachment)
                    }
                }
                // A file can be sent on its own, without a prompt.
                if !turn.prompt.isEmpty {
                    PromptBubble(text: turn.prompt)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            reply
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Motion.arrival(reduced: reduceMotion), value: turn.state)
        }
    }

    @ViewBuilder
    private var reply: some View {
        switch turn.state {
        case .running:
            if turn.kind == .image {
                GenerationPlaceholder(phase: phase, aspectRatio: turn.aspectRatio, preview: preview)
                    .transition(.opacity)
            } else {
                GenerationProgressLine(phase: phase)
                    .transition(.opacity)
            }
        case .audio(let item):
            AudioReplyMessage(item: item) {
                model.generation.regenerate(turn)
            }
            .transition(Motion.settle(reduced: reduceMotion))
        case .text(let text):
            TextReplyMessage(text: text) {
                model.generation.regenerate(turn)
            }
            .transition(Motion.settle(reduced: reduceMotion))
        case .finished(let item):
            GeneratedImageMessage(item: item, aspectRatio: turn.aspectRatio) {
                model.generation.regenerate(turn)
            }
            .transition(Motion.settle(reduced: reduceMotion))
        case .failed(let message):
            GenerationFailureMessage(kind: turn.kind, message: message) {
                model.generation.regenerate(turn)
            }
        case .cancelled:
            Label("Stopped", systemImage: "stop.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// The user's prompt, shown as a soft grey bubble.
struct PromptBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: 520, alignment: .trailing)
    }
}

/// A plain-language error in place of a reply, with a way to try again.
struct GenerationFailureMessage: View {
    let kind: MediaKind
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .symbolRenderingMode(.multicolor)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again", action: retry)
                .buttonStyle(SoftButtonStyle())
        }
        .frame(maxWidth: 520, alignment: .leading)
        .card(padding: 14)
    }

    private var title: String {
        switch kind {
        case .image: "The image could not be created"
        case .audio: "The audio could not be created"
        case .text: "The text could not be created"
        }
    }
}
