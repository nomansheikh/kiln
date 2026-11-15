import AppKit

/// Lets the composer's other controls reach the text view: to focus it, and to
/// put a sound where the cursor is.
@MainActor
final class SpeechEditorProxy {
    weak var view: NSTextView?

    func focus() {
        guard let view else { return }
        view.window?.makeFirstResponder(view)
    }

    /// Puts a mark at the cursor, spaced from the words around it. False when there is no text view.
    func insert(_ mark: String) -> Bool {
        guard let view else { return false }
        let text = view.string as NSString
        let range = view.selectedRange()
        let before = range.location > 0 ? text.substring(with: NSRange(location: range.location - 1, length: 1)) : " "
        let end = range.location + range.length
        let after = end < text.length ? text.substring(with: NSRange(location: end, length: 1)) : ""
        let isSpace = { (character: String) in character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let insertion = (isSpace(before) ? "" : " ") + mark + (after.isEmpty || !isSpace(after) ? " " : "")
        // Through the text view, so that it can be undone.
        view.insertText(insertion, replacementRange: range)
        focus()
        return true
    }
}
