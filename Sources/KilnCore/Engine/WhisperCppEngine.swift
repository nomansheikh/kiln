import Foundation

/// Turns speech into text with whisper.cpp, through the `kiln-whisper` helper process.
///
/// It works like `StableDiffusionCppEngine`: the helper stays alive between
/// requests so the model stays loaded, and a crashed helper is replaced on the
/// next request.
public actor WhisperCppEngine: InferenceEngine {
    public static let engineID = "whisper.cpp"

    private struct Job {
        let id: UUID
        let continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation
        let files: [URL]
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

    public init(
        helperURL: URL,
        storage: ModelStorage,
        scratchDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-whisper"),
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
            guard missing.isEmpty, let model = recipe.components.first(where: { $0.role == .model }) else {
                throw EngineError.missingComponents(missing.isEmpty ? ["the model file"] : missing)
            }
            guard let attachment = request.attachment else { throw EngineError.missingAudio }

            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            let audio = scratchDirectory.appendingPathComponent("\(id.uuidString).f32")
            let output = scratchDirectory.appendingPathComponent("\(id.uuidString).txt")
            try AudioSamples.write(attachment, to: audio)
            let command = try EngineMessage.transcribeCommand(
                model: storage.url(for: model), audio: audio, prompt: request.prompt, output: output
            )

            do {
                try launchHelperIfNeeded()
                job = Job(id: id, continuation: continuation, files: [audio, output])
                recentLog.removeAll()
                try input?.write(contentsOf: command)
            } catch {
                try? FileManager.default.removeItem(at: audio)
                throw error
            }
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
        case .ready, .image, .preview:
            break
        case .loading:
            job.continuation.yield(.loadingModel)
        case .progress(let stage, let completed, let total):
            let progress = GenerationProgress(stage: EngineMessage.stage(stage), completed: completed, total: total)
            job.continuation.yield(.progress(progress))
        case .text(let path):
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                finish(throwing: EngineError.invalidOutput)
                return
            }
            job.continuation.yield(.finished(.text(text.trimmingCharacters(in: .whitespacesAndNewlines))))
            finish()
        case .cancelled:
            finish(throwing: CancellationError())
        case .error(let code, let message):
            let detail = logTail.isEmpty ? message : logTail
            if EngineMessage.indicatesOutOfMemory(recentLog) {
                finish(throwing: EngineError.outOfMemory)
            } else if code == "load_failed" {
                finish(throwing: EngineError.modelLoadFailed(detail: logTail))
            } else {
                finish(throwing: EngineError.generationFailed(detail: detail))
            }
        case .idle:
            // A job that reaches idle without text or an error produced nothing.
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

    /// The last few log lines, for showing under a plain-language message.
    private var logTail: String {
        let errors = recentLog.filter { $0.localizedCaseInsensitiveContains("error") || $0.contains("failed") }
        return errors.suffix(3).joined(separator: "\n")
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
        for file in job.files {
            try? FileManager.default.removeItem(at: file)
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
