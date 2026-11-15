import Foundation

/// One helper process and the job it is running, shared by every engine that
/// works through a helper.
///
/// The helper stays alive between jobs so the model stays loaded. If it
/// crashes, the failure is reported and a fresh helper starts on the next job.
actor HelperSession {
    /// What an engine makes of one of its helper's own events.
    enum Step {
        case yield(GenerationEvent)
        case finish(GenerationOutput)
        case fail(EngineError)
    }

    /// Turns an event only this engine's helper sends, such as a finished image,
    /// into a step. Nil leaves the event to the session.
    typealias Interpreter = @Sendable (EngineMessage.Event) -> Step?

    struct Job {
        let id: UUID
        let continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation
        /// Scratch files exchanged with the helper, removed when the job ends.
        let files: [URL]
        let interpret: Interpreter
        var cancelRequested = false
        /// An error the helper reported whose reason has not been logged yet.
        var pendingError: (code: String, message: String)?
    }

    private let helperURL: URL
    /// What the helper is started with: the folders it confines itself to.
    private let arguments: [String]
    private let cancelGracePeriod: Duration
    let logTail: @Sendable ([String]) -> String

    var process: Process?
    var input: FileHandle?
    var launchID = UUID()
    var job: Job?
    var recentLog: [String] = []
    /// The helper reports `idle` after every job. Jobs that already ended still have one on the way.
    var pendingIdleEvents = 0

    /// - Parameters:
    ///   - arguments: Passed to the helper when it is started.
    ///   - cancelGracePeriod: How long a cancelled job may take to stop before the
    ///     helper is killed. Loading a model cannot be interrupted any other way.
    ///   - logTail: Picks the lines of the helper's recent log that describe a failure.
    init(
        helperURL: URL, arguments: [String] = [], cancelGracePeriod: Duration,
        logTail: @escaping @Sendable ([String]) -> String
    ) {
        self.helperURL = helperURL
        self.arguments = arguments
        self.cancelGracePeriod = cancelGracePeriod
        self.logTail = logTail
    }

    var isBusy: Bool { job != nil }

    // MARK: - Running a job

    /// Sends a command to the helper, starting it if needed. The outcome arrives
    /// on `continuation`; `files` are removed when the job ends, however it ends.
    func run(
        id: UUID,
        command: Data,
        files: [URL],
        continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation,
        interpret: @escaping Interpreter
    ) {
        do {
            guard job == nil else { throw EngineError.busy }
            try launchHelperIfNeeded()
            job = Job(id: id, continuation: continuation, files: files, interpret: interpret)
            recentLog.removeAll()
            try input?.write(contentsOf: command)
        } catch {
            if job?.id == id {
                // The helper died between launch and the first write.
                finish(throwing: EngineError.helperUnavailable(error.localizedDescription))
                stopHelper()
            } else {
                Self.remove(files)
                continuation.finish(throwing: error)
            }
        }
    }

    func cancel(_ id: UUID) {
        guard job?.id == id else { return }
        job?.cancelRequested = true
        try? input?.write(contentsOf: EngineMessage.cancelCommand)

        Task {
            try? await Task.sleep(for: cancelGracePeriod)
            self.killIfStillRunning(id)
        }
    }

    /// Ends the running job as cancelled and stops the helper, freeing the model.
    func shutdown() {
        finish(throwing: CancellationError())
        stopHelper()
    }

    private func launchHelperIfNeeded() throws {
        if let process, process.isRunning { return }
        let helper = try HelperProcess.launch(helperURL, arguments: arguments)
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
        // A helper taken over by a hostile model file must not get the app to read a
        // file the job never gave it. A preview is a nicety, so such a one is skipped.
        if let path = event.path, !job.files.contains(where: { Self.isSameFile($0, path) }) {
            if case .preview = event { return }
            finish(throwing: EngineError.invalidOutput)
            return stopHelper()
        }
        if let step = job.interpret(event) {
            switch step {
            case .yield(let event):
                job.continuation.yield(event)
            case .finish(let output):
                job.continuation.yield(.finished(output))
                finish()
            case .fail(let error):
                finish(throwing: error)
            }
            return
        }
        switch event {
        case .loading:
            job.continuation.yield(.loadingModel)
        case .progress(let stage, let completed, let total):
            let progress = GenerationProgress(stage: EngineMessage.stage(stage), completed: completed, total: total)
            job.continuation.yield(.progress(progress))
        case .cancelled:
            finish(throwing: CancellationError())
        case .error(let code, let message):
            fail(code: code, message: message)
        case .idle:
            // A job that reaches idle without a result or an error produced nothing.
            finish(throwing: EngineError.generationFailed(detail: ""), idleStillExpected: false)
        default:
            // Results of another kind of helper, and `ready`.
            break
        }
    }

    // MARK: - Ending a job

    private func killIfStillRunning(_ id: UUID) {
        guard job?.id == id else { return }
        finish(throwing: CancellationError())
        stopHelper()
    }

    func finish(throwing error: Error? = nil, idleStillExpected: Bool = true) {
        guard let job else { return }
        self.job = nil
        Self.remove(job.files)
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

    private static func isSameFile(_ file: URL, _ path: String) -> Bool {
        file.resolvingSymlinksInPath().path == URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func remove(_ files: [URL]) {
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
