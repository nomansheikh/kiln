import SwiftUI

/// The wrapping row of starter prompts shown in the hero layout.
struct PromptSuggestionChips: View {
    let onSelect: (PromptSuggestion) -> Void

    var body: some View {
        GenerateFlowLayout(spacing: 8) {
            ForEach(PromptSuggestion.all) { suggestion in
                PromptSuggestionChip(suggestion: suggestion) { onSelect(suggestion) }
            }
        }
    }
}

/// One outlined capsule naming a starter prompt.
private struct PromptSuggestionChip: View {
    let suggestion: PromptSuggestion
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(suggestion.title)
                .lineLimit(1)
                .font(.callout)
                .foregroundStyle(hovering ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(hovering ? Theme.card : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(suggestion.prompt)
    }
}
