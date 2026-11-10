#if DEBUG
import AppKit
import KilnCore

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
        if ProcessInfo.processInfo.arguments.contains("--sample-downloads"), let recipe = model.library.recipes.first {
            let total = recipe.totalSizeBytes ?? 1_000
            model.library.loadPreview(
                statuses: [recipe.id: DownloadStatus(state: .downloading, receivedBytes: total * 35 / 100, totalBytes: total,
                                                     currentFile: recipe.components.first?.file)],
                speeds: [recipe.id: DownloadSpeed(bytesPerSecond: 12_400_000, secondsRemaining: 487)]
            )
        }
        if ProcessInfo.processInfo.arguments.contains("--sample-thread") {
            loadSampleThread(into: model)
        }
        for item in SidebarItem.allCases {
            model.selection = item
            try? await Task.sleep(for: .seconds(item == .models ? 4 : 1.2))
            guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView?.superview,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("\(item.rawValue).png"))
        }
        NSApp.terminate(nil)
    }

    /// A finished, a failed and a running turn, so every thread state can be seen without a model.
    private static func loadSampleThread(into model: AppModel) {
        let side = 256
        var pixels = Data(capacity: side * side * 3)
        for y in 0..<side {
            for x in 0..<side {
                pixels.append(contentsOf: [UInt8(x), UInt8(y), UInt8(255 - (x + y) / 2)])
            }
        }
        let request = GenerationRequest(prompt: "A misty alpine lake at dawn, pine forest reflected in still water",
                                        width: 1024, height: 1024, steps: 8, cfg: 1, sampler: "euler", seed: 1234)
        let store = GalleryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("kiln-sample-thread"))
        let record = GenerationRecord(recipeID: "sample", recipeName: "Sample Model", request: request, durationSeconds: 12.4)
        let image = GeneratedImage(width: side, height: side, channels: 3, pixels: pixels)
        var turns: [GenerationTurn] = []
        if let item = try? store.save(image, record: record) {
            turns.append(GenerationTurn(item))
        }
        turns.append(GenerationTurn(prompt: "A portrait of a red fox, dramatic rim lighting", width: 1024, height: 1024,
                                    state: .failed("This Mac ran out of memory. Try a smaller image size, a smaller quantization, or close other apps.")))
        turns.append(GenerationTurn(prompt: "A rain-soaked city street at night, neon signs reflected in puddles", width: 1536, height: 1024))
        let roughPixels = Data((0..<768).map { (index: Int) -> UInt8 in
            let value: Int = (index * 37) % 200 + 30
            return UInt8(value)
        })
        let rough = GeneratedImage(width: 16, height: 16, channels: 3,
                                   pixels: roughPixels)
        model.generation.loadPreview(turns: turns, phase: .running(GenerationProgress(stage: .sampling, completed: 3, total: 8)), preview: rough)
    }
}
#endif
