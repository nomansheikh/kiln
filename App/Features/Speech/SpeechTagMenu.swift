import SwiftUI

/// The composer's chip that lists the marks a model understands inside the
/// text, such as a laugh or a sigh, and adds the chosen one to the text.
struct SpeechTagMenu: View {
    /// The marks as they are typed, such as `[laughter]`.
    let tags: [String]
    @Binding var text: String
    let editor: SpeechEditorProxy

    var body: some View {
        Menu {
            Section("Add where the cursor is") {
                ForEach(tags, id: \.self) { tag in
                    Button { add(tag) } label: {
                        Text(verbatim: Self.title(tag))
                    }
                }
            }
        } label: {
            ComposerChip(systemImage: "face.smiling", title: "Sounds")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointerCursor()
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .help("Add a sound this model can make. You can also type one where you want it, such as [laughs].")
        .accessibilityLabel("Sounds")
    }

    private func add(_ tag: String) {
        if editor.insert(tag) { return }
        let needsSpace = !(text.isEmpty || text.last?.isWhitespace == true)
        text += (needsSpace ? " " : "") + tag + " "
    }

    /// A mark as it is typed with a plain name beside it, such as "Laughter  [laughter]".
    static func title(_ tag: String) -> String {
        let words = tag.trimmingCharacters(in: CharacterSet(charactersIn: "[]<>(){}"))
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard !words.isEmpty, words != tag else { return tag }
        return "\(words.prefix(1).uppercased())\(words.dropFirst())   \(tag)"
    }
}
