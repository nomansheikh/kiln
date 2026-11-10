import AppKit

/// Quits the app when its window is closed, so a closed window never leaves a
/// model in memory. The engine helper exits with the app, which frees it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Returns true while work is running that closing the window should not interrupt.
    @MainActor static var hasWorkInProgress: () -> Bool = { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Self.hasWorkInProgress()
    }
}
