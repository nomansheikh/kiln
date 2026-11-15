import Foundation

/// Marks written inside text to be spoken, such as `[laughs]`.
///
/// Each model spells its marks its own way (`[laughter]`, `<laugh>`) and most
/// models know none. So that one way of writing works with every model, a mark
/// is rewritten to the model's spelling, or left out when the model has no such
/// sound: a model would otherwise read the word aloud.
public enum SpeechMarks {
    /// One word in square or angle brackets. Anything with a space or a digit,
    /// such as `[citation needed]` or `[S1]`, is ordinary text.
    private static let pattern = try? NSRegularExpression(pattern: #"\[([A-Za-z][A-Za-z_-]{1,30})\]|<([A-Za-z][A-Za-z_-]{1,30})>"#)

    /// One mark found in a text.
    public struct Mark: Sendable, Equatable {
        /// Where it is, brackets included, in UTF-16 units as text views count them.
        public var range: NSRange
        /// The mark as it was written, such as `[laughs]`.
        public var written: String
        /// The model's own spelling of it, or nil when the model has no such sound.
        public var tag: String?
    }

    /// The marks in `text`, in order, for a model that understands `tags`.
    public static func marks(in text: String, tags: [String]) -> [Mark] {
        guard let pattern else { return [] }
        let source = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            let inner = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            return Mark(range: match.range, written: source.substring(with: match.range),
                        tag: tag(for: source.substring(with: inner), in: tags))
        }
    }

    /// `text` as a model that understands `tags` should be given it.
    public static func apply(to text: String, tags: [String]) -> String {
        let found = marks(in: text, tags: tags)
        let source = text as NSString
        var result = ""
        var position = 0
        for mark in found {
            result += source.substring(with: NSRange(location: position, length: mark.range.location - position))
            position = mark.range.location + mark.range.length
            result += mark.tag ?? ""
        }
        result += source.substring(from: position)
        return found.contains { $0.tag == nil } ? tidied(result) : result
    }

    /// The model's mark for a word: the one spelled the same, or else the first
    /// that is the same word in another form, so `laughs` finds `[laughter]` and
    /// `surprise` finds `[surprise-ah]`.
    static func tag(for word: String, in tags: [String]) -> String? {
        let wanted = key(word)
        let keys = tags.map { key($0.trimmingCharacters(in: CharacterSet(charactersIn: "[]<>"))) }
        if let exact = keys.firstIndex(of: wanted) { return tags[exact] }
        let root = stem(wanted)
        let sameWord = keys.firstIndex { stem($0) == root }
            ?? keys.firstIndex { stem(String($0.prefix { $0 != "-" })) == root }
        return sameWord.map { tags[$0] }
    }

    /// A word without its ending, so that "laughs", "laughing" and "laughter" are one word.
    private static func stem(_ word: String) -> String {
        for ending in ["ing", "ter", "ed", "s"] where word.hasSuffix(ending) && word.count - ending.count >= 4 {
            return String(word.dropLast(ending.count))
        }
        return word
    }

    private static func key(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "_", with: "-")
    }

    /// Closes the gap a removed mark leaves behind.
    private static func tidied(_ text: String) -> String {
        text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
