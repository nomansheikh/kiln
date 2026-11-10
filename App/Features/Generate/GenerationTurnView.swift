import KilnCore
import SwiftUI

/// One exchange: the prompt on the right, the reply on the left.
struct GenerationTurnView: View {
    @Environment(AppModel.self) private var model
    let turn: GenerationTurn
    /// Progress of the running generation, used when this turn is the one running.
    let phase: GenerationPhase
    let preview: GeneratedImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PromptBubble(text: turn.prompt)
                .frame(maxWidth: .infinity, alignment: .trailing)
            reply
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth(duration: 0.6), value: turn.state)
        }
    }

    @ViewBuilder
    private var reply: some View {
        switch turn.state {
        case .running:
            GenerationPlaceholder(phase: phase, aspectRatio: turn.aspectRatio, preview: preview)
                .transition(.opacity)
        case .finished(let item):
            GeneratedImageMessage(item: item, aspectRatio: turn.aspectRatio) {
                model.generation.regenerate(turn)
            }
            .transition(.opacity)
        case .failed(let message):
            GenerationFailureMessage(message: message) {
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

/// A plain-language error in place of an image, with a way to try again.
struct GenerationFailureMessage: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("The image could not be created", systemImage: "exclamationmark.triangle.fill")
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
}
