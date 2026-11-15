import KilnCore
import SwiftUI

/// The composer's style chip for a model that takes fixed words instead of a
/// free description: one word may be chosen from each group, such as an age.
struct SpeechStyleMenu: View {
    let groups: [ModelRecipe.StyleGroup]
    /// The chosen words, at most one per group.
    @Binding var chosen: [String]

    var body: some View {
        let current = groups.compactMap { group in group.options.first(where: chosen.contains) }
        Menu {
            ForEach(groups, id: \.name) { group in
                Menu(group.name) {
                    ForEach(group.options, id: \.self) { word in
                        Button { toggle(word, in: group) } label: {
                            if current.contains(word) {
                                Label(Self.title(word), systemImage: "checkmark")
                            } else {
                                Text(verbatim: Self.title(word))
                            }
                        }
                    }
                }
            }
            if !current.isEmpty {
                Divider()
                Button("Clear") { chosen = [] }
            }
        } label: {
            ComposerChip(systemImage: "theatermasks", title: Self.summary(current), active: !current.isEmpty)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointerCursor()
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .help(current.isEmpty ? "Choose what the voice is like" : current.map(Self.title).joined(separator: ", "))
        .accessibilityLabel("Style")
        .accessibilityValue(current.isEmpty ? "None" : current.joined(separator: ", "))
    }

    /// Chooses a word in place of its group's current one; choosing it again clears the group.
    private func toggle(_ word: String, in group: ModelRecipe.StyleGroup) {
        let wasChosen = chosen.contains(word)
        chosen.removeAll(where: group.options.contains)
        if !wasChosen { chosen.append(word) }
    }

    private static func title(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    /// The chip's text: the first chosen word and how many more there are.
    private static func summary(_ current: [String]) -> String {
        guard let first = current.first else { return "Style" }
        return current.count == 1 ? title(first) : "\(title(first)) +\(current.count - 1)"
    }
}
