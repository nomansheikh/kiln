import AppKit
import SwiftUI

/// Gives the window a taller, empty unified title area so the traffic lights
/// sit inside the floating sidebar instead of on its rounded corner.
///
/// In full screen that title area becomes an opaque bar drawn over the
/// content, so it is hidden there and restored on the way back.
struct WindowChrome: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            let toolbar = NSToolbar(identifier: "kiln.main")
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = true
            context.coordinator.observe(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class Coordinator {
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

        func observe(_ window: NSWindow) {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak window] _ in
                    MainActor.assumeIsolated { window?.toolbar?.isVisible = false }
                },
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak window] _ in
                    MainActor.assumeIsolated { window?.toolbar?.isVisible = true }
                },
            ]
            if window.styleMask.contains(.fullScreen) {
                window.toolbar?.isVisible = false
            }
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
