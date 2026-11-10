import AppKit

extension NSPasteboard {
    /// Replaces the pasteboard's contents with a plain string.
    func copyText(_ text: String) {
        clearContents()
        setString(text, forType: .string)
    }
}
