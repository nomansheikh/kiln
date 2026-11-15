import SwiftUI

/// The composer's chip that shows the voice a speech model will use and picks another.
struct GenerationVoiceMenu: View {
    let voices: [String]
    @Binding var selection: String?

    var body: some View {
        let current = selection.flatMap { voices.contains($0) ? $0 : nil } ?? voices.first
        Menu {
            ForEach(voices, id: \.self) { voice in
                Button {
                    selection = voice
                } label: {
                    if voice == current {
                        Label(Self.title(voice), systemImage: "checkmark")
                    } else {
                        Text(verbatim: Self.title(voice))
                    }
                }
            }
        } label: {
            ComposerChip(systemImage: "person.wave.2", title: current.map(Self.title) ?? "Voice")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointerCursor()
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .help("Voice")
        .accessibilityLabel("Voice")
        .accessibilityValue(current.map(Self.title) ?? "")
    }

    /// A voice name as people read it: `bill_boerst` becomes "Bill Boerst".
    static func title(_ voice: String) -> String {
        voice.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
