#if DEBUG
import AppKit

/// Debug builds only: `Kiln --snapshot <folder>` saves a PNG of each screen and quits.
/// The app draws its own window, so no screen-recording permission is needed.
@MainActor
enum DebugSnapshot {
    static var outputDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) else { return nil }
        return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
    }

    static func run(model: AppModel, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(1.5))
        for item in SidebarItem.allCases {
            model.selection = item
            try? await Task.sleep(for: .seconds(1.2))
            guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView?.superview,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("\(item.rawValue).png"))
        }
        NSApp.terminate(nil)
    }
}
#endif
