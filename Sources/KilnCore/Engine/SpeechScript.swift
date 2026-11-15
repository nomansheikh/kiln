import Foundation

/// A text to be spoken by several speakers, written the way a script is:
///
///     Anna: Did you hear that?
///     Ben: Hear what?
///
/// A line that starts with a short name and a colon begins that speaker's
/// turn; the lines after it belong to the same turn. Each model wants its own
/// spelling (`Speaker 1: …`, `[S1] …`), so the script is rewritten for the
/// model, and the names are the user's to choose.
public struct SpeechScript: Sendable, Equatable {
    /// What one speaker says before the next one starts.
    public struct Turn: Sendable, Equatable {
        /// The speaker's name as it was first written.
        public var speaker: String
        public var text: String
        /// How the turn is said, written in brackets after the name: `Anna (whispering): …`.
        public var note: String?
        /// Where the name and its colon are, in UTF-16 units as text views count
        /// them. Nil for text before the first name.
        public var label: NSRange?
    }

    /// The name of whoever speaks text that has no name in front of it.
    public static let unnamedSpeaker = "Speaker 1"

    public var turns: [Turn] = []
    /// The speakers' names, in the order they first speak.
    public var speakers: [String] = []

    /// At most three words without sentence punctuation, an optional note in
    /// brackets, then a colon followed by a space or the end of the line. So
    /// "10:30" and "https://" are not names.
    private static let pattern = try? NSRegularExpression(
        pattern: #"^[ \t]*((?:[^\s:.,!?;()\[\]<>]+[ \t]+){0,2}[^\s:.,!?;()\[\]<>]+)[ \t]*(?:\(([^)\n]{1,60})\))?[ \t]*:(?=[ \t]|$)"#,
        options: .anchorsMatchLines
    )

    public init(_ text: String) {
        let source = text as NSString
        let whole = NSRange(location: 0, length: source.length)
        let labels = (Self.pattern?.matches(in: text, range: whole) ?? []).filter { $0.range(at: 1).length <= 30 }

        var names: [String: String] = [:]
        func add(_ written: String, _ said: String, note: String? = nil, label: NSRange?) {
            let key = Self.key(written)
            if names[key] == nil {
                names[key] = written
                speakers.append(written)
            }
            // A turn may run over several lines; a model reads it as one.
            let words = said.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            turns.append(Turn(speaker: names[key] ?? written, text: words, note: note, label: label))
        }

        let firstLabel = labels.first?.range.location ?? source.length
        let opening = source.substring(to: firstLabel)
        if !opening.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(Self.unnamedSpeaker, opening, label: nil)
        }
        for (index, match) in labels.enumerated() {
            let start = match.range.location + match.range.length
            let end = index + 1 < labels.count ? labels[index + 1].range.location : source.length
            let note = match.range(at: 2).location == NSNotFound
                ? nil : source.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            add(source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces),
                source.substring(with: NSRange(location: start, length: end - start)),
                note: note?.isEmpty == false ? note : nil, label: match.range)
        }
    }

    /// True when more than one speaker talks, which is what makes a text a script.
    public var isDialogue: Bool { speakers.count > 1 }

    /// The speaker's place among `speakers`, whatever the case it is written in.
    public func index(of speaker: String) -> Int? {
        speakers.firstIndex { Self.key($0) == Self.key(speaker) }
    }

    /// The script as a model reads it: one line per turn, in the model's own
    /// spelling, with the speakers numbered from 1 in the given order.
    public func rendered(line: String, order: [String]? = nil) -> String {
        let order = (order ?? speakers).map(Self.key)
        return turns.filter { !$0.text.isEmpty }.map { turn in
            let number = (order.firstIndex(of: Self.key(turn.speaker)) ?? 0) + 1
            return line.replacingOccurrences(of: "{n}", with: String(number)).replacingOccurrences(of: "{text}", with: turn.text)
        }.joined(separator: "\n")
    }

    /// One name for "Anna", "anna" and "ANNA".
    public static func key(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
