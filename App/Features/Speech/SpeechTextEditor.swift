import AppKit
import KilnCore
import SwiftUI

/// The Speech composer's text field. It is a text view instead of a SwiftUI
/// field so that marks such as `[laughs]` can be coloured as they are typed:
/// in the accent colour when the model has the sound, struck through when it
/// will be left out, and the names of a script's speakers each in a colour
/// of their own. Return sends; Shift-Return or Option-Return adds a line.
struct SpeechTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// The selected model's own marks.
    let tags: [String]
    /// True when the text is read as a script, whose speakers' names are coloured.
    var showsSpeakers = false
    let proxy: SpeechEditorProxy
    /// The height the text needs, for the composer to grow with it.
    @Binding var height: CGFloat
    /// Whether the field has the keyboard, for the composer's border.
    @Binding var isFocused: Bool
    let onSubmit: () -> Void

    static let font = NSFont.systemFont(ofSize: 15)
    private static let lineSpacing: CGFloat = 3
    /// The height of a number of lines, for the field's smallest and largest size.
    static func height(ofLines lines: Int) -> CGFloat {
        CGFloat(lines) * (NSLayoutManager().defaultLineHeight(for: font) + lineSpacing)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FocusReportingTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Self.lineSpacing
        view.delegate = context.coordinator
        (view as? FocusReportingTextView)?.onFocusChange = { [coordinator = context.coordinator] focused in
            // Focus can change during a view update, which must not change state.
            let parent = coordinator.parent
            DispatchQueue.main.async { parent.isFocused = focused }
        }
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.font = Self.font
        view.textColor = .labelColor
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: Self.font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.setAccessibilityLabel("Text to read aloud")
        view.string = text
        proxy.view = view
        context.coordinator.refresh(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        context.coordinator.refresh(view)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SpeechTextEditor

        init(_ parent: SpeechTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            refresh(view)
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Option-Return arrives as a different command and adds a line as usual.
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            // Shift-Return adds a line too, as it does in most places text is sent from.
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                view.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            parent.onSubmit()
            return true
        }

        /// Colours the marks and the speakers' names, and reports the height the text needs.
        func refresh(_ view: NSTextView) {
            guard let layout = view.layoutManager, let container = view.textContainer else { return }
            let whole = NSRange(location: 0, length: (view.string as NSString).length)
            // Temporary attributes colour the text without changing it, so undo
            // and a text being composed from several keys are left alone.
            for name in [NSAttributedString.Key.foregroundColor, .strikethroughStyle, .backgroundColor] {
                layout.removeTemporaryAttribute(name, forCharacterRange: whole)
            }
            for mark in SpeechMarks.marks(in: view.string, tags: parent.tags) {
                if mark.tag != nil {
                    layout.addTemporaryAttributes([
                        .foregroundColor: NSColor(Theme.accent),
                        .backgroundColor: NSColor(Theme.accent).withAlphaComponent(0.14),
                    ], forCharacterRange: mark.range)
                } else {
                    layout.addTemporaryAttributes([
                        .foregroundColor: NSColor.tertiaryLabelColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    ], forCharacterRange: mark.range)
                }
            }
            if parent.showsSpeakers {
                let script = SpeechScript(view.string)
                for turn in script.turns {
                    guard let label = turn.label else { continue }
                    let hue = VoiceAvatar.hue(ofSpeaker: script.index(of: turn.speaker) ?? 0)
                    let colour = NSColor(hue: hue, saturation: 0.6, brightness: 0.85, alpha: 1)
                    layout.addTemporaryAttributes([.foregroundColor: colour], forCharacterRange: label)
                }
            }
            layout.ensureLayout(for: container)
            let needed = ceil(layout.usedRect(for: container).height)
            if abs(needed - parent.height) > 0.5 {
                // The height is state of the view above, which cannot change during its update.
                DispatchQueue.main.async { [parent] in parent.height = needed }
            }
        }
    }
}

/// A text view that says when it gets and loses the keyboard.
final class FocusReportingTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }
}
