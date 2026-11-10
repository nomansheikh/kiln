import Foundation

/// Runs stable-diffusion.cpp through the `kiln-engine` helper process.
///
/// The helper stays alive between generations so the model stays loaded.
/// If it crashes, the failure is reported and a fresh helper starts on the
/// next request.
public actor StableDiffusionCppEngine: InferenceEngine {
    public static let engineID = "sd.cpp"

    private struct Job {
        let id: UUID
        let continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation
        let previewFile: URL
        let initFile: URL?
        var cancelRequested = false
    }

    private let helperURL: URL
    private let storage: ModelStorage
    private let scratchDirectory: URL
    private let cancelGracePeriod: Duration

    private var process: Process?
    private var input: FileHandle?
    private var launchID = UUID()
    private var job: Job?
    private var recentLog: [String] = []
    /// The helper reports `idle` after every job. Jobs that already ended still have one on the way.
    private var pendingIdleEvents = 0

    /// - Parameter cancelGracePeriod: How long a cancelled generation may take to stop
    ///   before the helper is killed. Loading a model cannot be interrupted any other way.
    public init(
        helperURL: URL,
        storage: ModelStorage,
        scratchDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-engine"),
        cancelGracePeriod: Duration = .seconds(3)
    ) {
        self.helperURL = helperURL
        self.storage = storage
        self.scratchDirectory = scratchDirectory
        self.cancelGracePeriod = cancelGracePeriod
    }

    public nonisolated func generate(
        recipe: ModelRecipe,
        request: GenerationRequest
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] reason in
                guard case .cancelled = reason else { return }
                Task { await self?.cancel(id) }
            }
            Task { await self.start(id: id, recipe: recipe, request: request, continuation: continuation) }
        }
    }

    public func shutdown() {
        finish(throwing: CancellationError())
        stopHelper()
    }

    // MARK: - Starting a job

    private func start(
        id: UUID,
        recipe: ModelRecipe,
        request: GenerationRequest,
        continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation
    ) {
        do {
            guard job == nil else { throw EngineError.busy }
            guard recipe.engine == Self.engineID else { throw EngineError.unsupportedEngine(recipe.engine) }
            let missing = storage.missingComponents(of: recipe).map(\.file)
            guard missing.isEmpty else { throw EngineError.missingComponents(missing) }

            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            let output = scratchDirectory.appendingPathComponent("\(id.uuidString).raw")
            let previewFile = scratchDirectory.appendingPathComponent("\(id.uuidString).preview")
            let initFile = try prepareSourceImage(for: request, id: id)
            let command = try EngineMessage.generateCommand(
                recipe: recipe, storage: storage, request: request, output: output, preview: previewFile, initImage: initFile
            )

            try launchHelperIfNeeded()
            job = Job(id: id, continuation: continuation, previewFile: previewFile, initFile: initFile)
            recentLog.removeAll()
            try input?.write(contentsOf: command)
        } catch {
            if job?.id == id {
                // The helper died between launch and the first write.
                finish(throwing: EngineError.helperUnavailable(error.localizedDescription))
                stopHelper()
            } else {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Writes the request's source image as raw pixels at the output size, where the helper reads it.
    private func prepareSourceImage(for request: GenerationRequest, id: UUID) throws -> URL? {
        guard let source = request.sourceImage else { return nil }
        let file = scratchDirectory.appendingPathComponent("\(id.uuidString).init")
        do {
            try ImageCodec.rgbPixels(of: source, width: request.width, height: request.height).write(to: file)
        } catch {
            throw EngineError.unreadableSourceImage
        }
        return file
    }

    private func launchHelperIfNeeded() throws {
        if let process, process.isRunning { return }
        let helper = try HelperProcess.launch(helperURL)
        let id = UUID()
        launchID = id
        pendingIdleEvents = 0
        process = helper.process
        input = helper.input

        Task.detached { [weak self] in
            for await line in helper.events {
                if let event = EngineMessage.decodeEvent(line) {
                    await self?.handle(event, from: id)
                }
            }
            helper.process.waitUntilExit()
            await self?.helperExited(id)
        }
        Task.detached { [weak self] in
            for await line in helper.logs {
                await self?.log(line, from: id)
            }
        }
    }

    // MARK: - Helper events

    private func handle(_ event: EngineMessage.Event, from id: UUID) {
        guard id == launchID else { return }
        if event == .idle, pendingIdleEvents > 0 {
            pendingIdleEvents -= 1
            return
        }
        guard let job else { return }
        switch event {
        case .ready:
            break
        case .loading:
            job.continuation.yield(.loadingModel)
        case .progress(let stage, let completed, let total):
            let progress = GenerationProgress(stage: EngineMessage.stage(stage), completed: completed, total: total)
            job.continuation.yield(.progress(progress))
        case .preview(let path, let width, let height, let channels):
            // Previews are a nicety: one that cannot be read is skipped.
            if let image = GeneratedImage(rawFile: path, width: width, height: height, channels: channels) {
                job.continuation.yield(.preview(image))
            }
        case .image(let path, let width, let height, let channels):
            defer { try? FileManager.default.removeItem(atPath: path) }
            guard let image = GeneratedImage(rawFile: path, width: width, height: height, channels: channels) else {
                finish(throwing: EngineError.invalidOutput)
                return
            }
            job.continuation.yield(.finished(image))
            finish()
        case .cancelled:
            finish(throwing: CancellationError())
        case .error(let code, let message):
            finish(throwing: failure(code: code, message: message))
        case .idle:
            // A job that reaches idle without an image or an error produced nothing.
            finish(throwing: EngineError.generationFailed(detail: ""), idleStillExpected: false)
        }
    }

    private func log(_ line: String, from id: UUID) {
        guard id == launchID else { return }
        recentLog.append(line)
        if recentLog.count > 40 {
            recentLog.removeFirst(recentLog.count - 40)
        }
    }

    private func helperExited(_ id: UUID) async {
        guard id == launchID else { return }
        // Give the last log lines a moment to arrive before classifying the crash.
        try? await Task.sleep(for: .milliseconds(100))
        guard id == launchID else { return }
        process = nil
        input = nil
        guard let job else { return }
        if job.cancelRequested {
            finish(throwing: CancellationError())
        } else if EngineMessage.indicatesOutOfMemory(recentLog) {
            finish(throwing: EngineError.outOfMemory)
        } else {
            finish(throwing: EngineError.crashed(detail: logTail))
        }
    }

    private func failure(code: String, message: String) -> EngineError {
        if EngineMessage.indicatesOutOfMemory(recentLog) {
            return .outOfMemory
        }
        switch code {
        case "load_failed": return .modelLoadFailed(detail: logTail)
        default: return .generationFailed(detail: logTail.isEmpty ? message : logTail)
        }
    }

    /// The last few error lines, for showing under a plain-language message.
    private var logTail: String {
        let errors = recentLog.filter { $0.contains("[error]") }
        return (errors.isEmpty ? recentLog : errors).suffix(3).joined(separator: "\n")
    }

    // MARK: - Cancelling and stopping

    private func cancel(_ id: UUID) {
        guard job?.id == id else { return }
        job?.cancelRequested = true
        try? input?.write(contentsOf: EngineMessage.cancelCommand)

        Task {
            try? await Task.sleep(for: cancelGracePeriod)
            self.killIfStillRunning(id)
        }
    }

    private func killIfStillRunning(_ id: UUID) {
        guard job?.id == id else { return }
        finish(throwing: CancellationError())
        stopHelper()
    }

    private func finish(throwing error: Error? = nil, idleStillExpected: Bool = true) {
        guard let job else { return }
        self.job = nil
        try? FileManager.default.removeItem(at: job.previewFile)
        if let initFile = job.initFile {
            try? FileManager.default.removeItem(at: initFile)
        }
        if idleStillExpected {
            pendingIdleEvents += 1
        }
        job.continuation.finish(throwing: error)
    }

    private func stopHelper() {
        launchID = UUID()
        try? input?.close()
        process?.terminate()
        process = nil
        input = nil
    }
}
