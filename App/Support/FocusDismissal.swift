import AppKit

/// Takes the keyboard away from a text field when the user clicks somewhere else.
///
/// macOS leaves a field focused until another field takes over, so a click on
/// empty space changes nothing. Here a composer shows that it is focused, and
/// staying lit after a click elsewhere reads as a mistake. A click inside a
/// composer, on its buttons and menus as well as its text, keeps the focus.
@MainActor
final class FocusDismissal {
    static let shared = FocusDismissal()

    /// The frames of the composers, in the window's coordinates from its top-left corner.
    private var regions: [UUID: CGRect] = [:]
    private var monitor: Any?

    func setRegion(_ frame: CGRect?, for id: UUID) {
        regions[id] = frame
        start()
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        // Only a click in the window that holds the focused field counts: a
        // popover or a menu is a window of its own.
        guard let window = event.window, let content = window.contentView,
              let focused = window.firstResponder as? NSTextView
        else { return }
        let point = event.locationInWindow
        // A click on a text field, the focused one or another, is that field's business.
        var hit = content.hitTest(content.convert(point, from: nil))
        while let view = hit {
            if view === focused || view is NSTextField || view is NSTextView { return }
            hit = view.superview
        }
        let fromTop = CGPoint(x: point.x, y: content.bounds.height - point.y)
        guard !regions.values.contains(where: { $0.contains(fromTop) }) else { return }
        window.makeFirstResponder(nil)
    }
}
