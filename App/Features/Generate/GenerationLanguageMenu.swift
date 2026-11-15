import SwiftUI

/// The composer's chip for the language a speech model works in. It lists the
/// languages the model supports, with "Auto" first to let the model decide.
struct GenerationLanguageMenu: View {
    /// Language codes the model supports, such as `en`.
    let languages: [String]
    /// The chosen code, or nil for "Auto".
    @Binding var selection: String?

    var body: some View {
        let current = selection.flatMap { languages.contains($0) ? $0 : nil }
        Menu {
            choice("Auto", isOn: current == nil) { selection = nil }
            Divider()
            ForEach(Self.sorted(languages), id: \.self) { code in
                choice(Self.name(code), isOn: code == current) { selection = code }
            }
        } label: {
            ComposerChip(systemImage: "globe", title: current.map(Self.name) ?? "Auto", active: current != nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointerCursor()
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .help(current == nil ? "Language: the model decides" : "Language")
        .accessibilityLabel("Language")
        .accessibilityValue(current.map(Self.name) ?? "Auto")
    }

    private func choice(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isOn {
                Label(title, systemImage: "checkmark")
            } else {
                Text(verbatim: title)
            }
        }
    }

    /// A language's name in the user's own language, such as "German" for `de`.
    /// A code the system does not know is shown as it is.
    static func name(_ code: String) -> String {
        let locale = Locale.current
        let name = locale.localizedString(forIdentifier: code) ?? locale.localizedString(forLanguageCode: code)
        return name.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? code
    }

    private static func sorted(_ codes: [String]) -> [String] {
        codes.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }
}
