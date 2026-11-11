#if DEBUG
import AppKit
import KilnCore

/// Debug builds only: `Kiln --snapshot <folder>` saves a PNG of each screen and quits.
/// The app draws its own window, so no screen-recording permission is needed.
@MainActor
enum DebugSnapshot {
    static var outputDirectory: URL? {
        directory(after: "--snapshot")
    }

    /// `--gallery <folder>` shows that folder as the gallery, so screenshots need not show the user's own images.
    static var galleryDirectory: URL? {
        directory(after: "--gallery")
    }

    private static func directory(after flag: String) -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
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
        // Every snapshot has the default window size, whatever size the window was left at.
        let window = NSApp.windows.first { $0.isVisible && $0.contentView != nil }
        let savedFrame = window?.frame
        window?.setContentSize(NSSize(width: 1220, height: 780))
        defer {
            if let savedFrame { window?.setFrame(savedFrame, display: false) }
            NSApp.terminate(nil)
        }
        for item in SidebarItem.allCases {
            model.selection = item
            try? await Task.sleep(for: .seconds(item == .models ? 4 : 1.2))
            guard let view = window?.contentView?.superview,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("\(item.rawValue).png"))
        }
    }

    /// A finished, a failed and a running turn, so every thread state can be seen without a model.
    /// With `--gallery`, the two oldest images of that folder as finished turns instead.
    private static func loadSampleThread(into model: AppModel) {
        if galleryDirectory != nil, !model.gallery.items.isEmpty {
            model.generation.loadPreview(turns: model.gallery.items.suffix(2).reversed().map { GenerationTurn($0) }, phase: .idle)
            return
        }
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
        let sampleImage = turns.first?.image?.url
        turns.append(GenerationTurn(prompt: "Make it a rainy night with neon reflections", width: 1536, height: 1024, attachment: sampleImage))
        let roughPixels = Data((0..<768).map { (index: Int) -> UInt8 in
            let value: Int = (index * 37) % 200 + 30
            return UInt8(value)
        })
        let rough = GeneratedImage(width: 16, height: 16, channels: 3,
                                   pixels: roughPixels)
        if let sampleImage {
            try? model.generation.attach(sampleImage)
        }
        model.generation.loadPreview(turns: turns, phase: .running(GenerationProgress(stage: .sampling, completed: 3, total: 8)), preview: rough)
    }
}
#endif
