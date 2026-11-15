import AppKit
import SwiftUI

/// Shows the pointing-hand cursor over something that can be clicked.
private struct PointerCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                set(inside && isEnabled)
            }
            // A view removed or disabled under the mouse gets no "left" event.
            .onDisappear { set(false) }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { set(false) }
            }
    }

    /// Cursors are a stack, so each push is matched by exactly one pop.
    private func set(_ show: Bool) {
        guard show != isShowing else { return }
        isShowing = show
        if show {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }
}

extension View {
    /// Shows the pointing-hand cursor while the mouse is over this view and it is enabled.
    func pointerCursor() -> some View {
        modifier(PointerCursor())
    }
}
