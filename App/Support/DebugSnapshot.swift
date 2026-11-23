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

    /// `--chats <folder>` shows that folder's chats in the sidebar instead of the user's own,
    /// so a screenshot does not publish what they wrote. An empty folder shows no chats.
    static var chatsDirectory: URL? {
        directory(after: "--chats")
    }

    /// `--audio <folder>` shows that folder's clips on the Speech screen instead of the user's own.
    static var audioDirectory: URL? {
        directory(after: "--audio")
    }

    /// `--open-voices` opens the Speech screen's voice list, or its speaker list for a model that reads a script, so a snapshot can include it.
    static var opensVoiceList: Bool {
        ProcessInfo.processInfo.arguments.contains("--open-voices")
    }

    /// `--voices <folder>` uses that folder as the user's own voices instead of the real one.
    static var voicesDirectory: URL? {
        directory(after: "--voices")
    }

    /// `--models <folder>` uses that folder as the downloaded models instead of the real one.
    static var modelsDirectory: URL? {
        directory(after: "--models")
    }

    /// `--open-style` opens the Speech screen's style editor, so a snapshot can include it.
    static var opensStyleEditor: Bool {
        ProcessInfo.processInfo.arguments.contains("--open-style")
    }

    /// `--sample-update` shows the sidebar's notice of a new version without asking GitHub.
    static var showsSampleUpdate: Bool {
        ProcessInfo.processInfo.arguments.contains("--sample-update")
    }

    /// `--only <screen>` limits a snapshot to one screen, named as in `SidebarItem`.
    private static var onlyItem: SidebarItem? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--only"), arguments.indices.contains(index + 1) else { return nil }
        return SidebarItem(rawValue: arguments[index + 1])
    }

    static func directory(after flag: String) -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    /// A copy started for a snapshot while another copy of Kiln is running sometimes
    /// gets no window, and then nothing is captured. Asking the app to reopen, as
    /// clicking its Dock icon does, makes it create one.
    static func openWindowIfMissing() {
        guard outputDirectory != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.contentView != nil }) else { return }
            let me = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
            let reopen = NSAppleEventDescriptor(
                eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication), targetDescriptor: me,
                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
            )
            _ = try? reopen.sendEvent(options: .noReply, timeout: 1)
        }
    }

    static func run(model: AppModel, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(1.5))
        if ProcessInfo.processInfo.arguments.contains("--sample-downloads"), let recipe = model.library.recipes.first {
            let total = recipe.totalSizeBytes ?? 1_000
            var statuses = [recipe.id: DownloadStatus(state: .downloading, receivedBytes: total * 35 / 100, totalBytes: total,
                                                      currentFile: recipe.components.first?.file)]
            // One of each ended state too, since those rows are laid out differently.
            let others = model.library.recipes.dropFirst().prefix(2)
            if let done = others.first {
                statuses[done.id] = DownloadStatus(state: .completed, receivedBytes: done.totalSizeBytes ?? 1_000,
                                                   totalBytes: done.totalSizeBytes, currentFile: nil)
            }
            if let failed = others.last, failed.id != others.first?.id {
                statuses[failed.id] = DownloadStatus(
                    state: .failed("The download stopped because the connection was lost. Try again."),
                    receivedBytes: 0, totalBytes: failed.totalSizeBytes, currentFile: nil
                )
            }
            model.library.loadPreview(
                statuses: statuses,
                speeds: [recipe.id: DownloadSpeed(bytesPerSecond: 12_400_000, secondsRemaining: 487)]
            )
        }
        // `--model <recipe id>` selects an installed model, so its controls can be seen.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--model"), arguments.indices.contains(index + 1),
           let recipe = model.library.installedRecipes.first(where: { $0.id == arguments[index + 1] }) {
            model.generation.selectRecipe(recipe)
            if recipe.task == .textToSpeech { model.speech.selectRecipe(recipe) }
        }
        if ProcessInfo.processInfo.arguments.contains("--sample-thread") {
            loadSampleThread(into: model)
        }
        if ProcessInfo.processInfo.arguments.contains("--sample-speech") {
            loadSampleSpeech(into: model)
        }
        if ProcessInfo.processInfo.arguments.contains("--sample-clips") {
            loadSampleClips(into: model)
        }
        if ProcessInfo.processInfo.arguments.contains("--sample-working") {
            model.speech.loadPreview(activity: .speaking)
        }
        loadSampleBuilding(into: model)
        // Every snapshot has the default window size, whatever size the window was left at.
        let window = NSApp.windows.first { $0.isVisible && $0.contentView != nil }
        let savedFrame = window?.frame
        window?.setContentSize(NSSize(width: 1220, height: 780))
        defer {
            if let savedFrame { window?.setFrame(savedFrame, display: false) }
            NSApp.terminate(nil)
            // An open sheet cancels quitting, which would leave this copy running.
            exit(0)
        }
        // `--speech-text <text>` fills the Speech screen's field, to show how marks in it are coloured.
        // `--add-voice` opens the sheet for adding a voice on the Speech screen.
        model.speech.isAddingVoice = ProcessInfo.processInfo.arguments.contains("--add-voice")
        // `--design-voice` opens the sheet for designing one.
        model.speech.isDesigningVoice = ProcessInfo.processInfo.arguments.contains("--design-voice")
        let words = ProcessInfo.processInfo.arguments
        if let index = words.firstIndex(of: "--speech-text"), words.indices.contains(index + 1) {
            model.speech.text = words[index + 1]
        }
        // `--send` reads that text aloud with the selected model and waits for the clip.
        if words.contains("--send") {
            model.selection = .speech
            model.speech.generate()
            while model.speech.isGenerating { try? await Task.sleep(for: .milliseconds(200)) }
        }
        for item in SidebarItem.allCases where onlyItem == nil || item == onlyItem {
            model.selection = item
            try? await Task.sleep(for: .seconds(item == .models ? 4 : 1.2))
            if item == .speech, opensVoiceList || opensStyleEditor {
                // The list opens a moment after the screen appears.
                try? await Task.sleep(for: .seconds(1.5))
            }
            save(window, as: item.rawValue, in: directory)
            if let sheet = window?.attachedSheet {
                save(sheet, as: "\(item.rawValue)-sheet", in: directory)
            }
            // A popover is a window of its own.
            let popovers = NSApp.windows.filter { $0 !== window && $0.isVisible && $0.className.contains("Popover") }
            for (index, popover) in popovers.enumerated() {
                save(popover, as: "\(item.rawValue)-popover\(index == 0 ? "" : "-\(index + 1)")", in: directory)
            }
            if item == .speech, model.speech.isGenerating {
                // A second frame shows whether the waveform is moving.
                try? await Task.sleep(for: .seconds(0.4))
                save(window, as: "\(item.rawValue)-later", in: directory)
            }
        }
    }

    private static func save(_ window: NSWindow?, as name: String, in directory: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
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
        let request = GenerationRequest(
            prompt: "A misty alpine lake at dawn, pine forest reflected in still water",
            image: ImageSettings(width: 1024, height: 1024, steps: 8, cfg: 1, sampler: "euler", seed: 1234)
        )
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
