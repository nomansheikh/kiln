import AppKit
import Observation
import SwiftUI

/// Tracks whether the user is moving around with the keyboard.
///
/// Focus rings are only useful while navigating with Tab. Without this, macOS
/// draws one on whichever control holds focus when a window or popover opens,
/// even for someone who only uses the mouse.
@MainActor
@Observable
final class KeyboardNavigationMonitor {
    static let shared = KeyboardNavigationMonitor()

    /// True from a Tab key press until the next mouse click.
    private(set) var isNavigating = false
    @ObservationIgnored private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            let navigating: Bool? = switch event.type {
            case .keyDown: event.keyCode == Self.tabKeyCode ? true : nil
            default: false
            }
            if let navigating {
                MainActor.assumeIsolated { self?.set(navigating) }
            }
            return event
        }
    }

    private func set(_ navigating: Bool) {
        if isNavigating != navigating {
            isNavigating = navigating
        }
    }

    private static let tabKeyCode: UInt16 = 48
}

extension View {
    /// Shows focus rings in this view only while the user is navigating with Tab.
    /// Popovers are separate windows and need this applied to their content too.
    func focusRingsWhileNavigating() -> some View {
        modifier(FocusRingPolicy())
    }
}

private struct FocusRingPolicy: ViewModifier {
    func body(content: Content) -> some View {
        content
            .focusEffectDisabled(!KeyboardNavigationMonitor.shared.isNavigating)
            .onAppear { KeyboardNavigationMonitor.shared.start() }
    }
}
