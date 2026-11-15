import KilnCore
import SwiftUI

/// The list a voice's traits are picked from: the groups on the left, and
/// the words of the group under the pointer on the right.
struct SpeechTraitOptions: View {
    let groups: [ModelRecipe.StyleGroup]
    let choose: (String, ModelRecipe.StyleGroup) -> Void
    @State private var selection: String?

    private var shown: ModelRecipe.StyleGroup? {
        groups.first { $0.name == selection } ?? groups.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(groups, id: \.name) { group in
                    SpeechTraitRow(title: group.name, isSelected: group.name == shown?.name, showsArrow: true) {
                        selection = group.name
                    } hover: {
                        selection = group.name
                    }
                }
            }
            .padding(8)
            .frame(width: 124)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let group = shown {
                        ForEach(group.options, id: \.self) { word in
                            SpeechTraitRow(title: Self.title(word, in: group), isSelected: false, showsArrow: false) {
                                choose(word, group)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(width: 168)
        }
        // One height for every group, so the list does not jump between them; a long group scrolls.
        .frame(height: CGFloat(max(min(groups.map(\.options.count).max() ?? 1, 6), groups.count)) * 32 + 14, alignment: .top)
    }

    /// The word without its group's name, which is shown beside it: "American" for "american accent".
    static func title(_ word: String, in group: ModelRecipe.StyleGroup) -> String {
        let ending = " " + group.name.lowercased()
        let short = word.lowercased().hasSuffix(ending) ? String(word.dropLast(ending.count)) : word
        return short.prefix(1).uppercased() + short.dropFirst()
    }
}

/// One row of the list: a group on the left or a word on the right.
private struct SpeechTraitRow: View {
    let title: String
    let isSelected: Bool
    let showsArrow: Bool
    let action: () -> Void
    var hover: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(verbatim: title)
                    .font(.callout.weight(isSelected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showsArrow {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                isSelected ? Theme.accent.opacity(0.14) : (hovering ? Theme.card : .clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { inside in
            hovering = inside
            if inside { hover() }
        }
    }
}
