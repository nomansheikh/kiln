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

    private struct Job {
        let id: UUID
        let continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation
        /// Scratch files exchanged with the helper, removed when the job ends.
        let files: [URL]
        let interpret: Interpreter
        var cancelRequested = false
    }

    private let helperURL: URL
    private let cancelGracePeriod: Duration
    private let logTail: @Sendable ([String]) -> String

    private var process: Process?
    private var input: FileHandle?
    private var launchID = UUID()
    private var job: Job?
    private var recentLog: [String] = []
    /// The helper reports `idle` after every job. Jobs that already ended still have one on the way.
    private var pendingIdleEvents = 0

    /// - Parameters:
    ///   - cancelGracePeriod: How long a cancelled job may take to stop before the
    ///     helper is killed. Loading a model cannot be interrupted any other way.
    ///   - logTail: Picks the lines of the helper's recent log that describe a failure.
    init(helperURL: URL, cancelGracePeriod: Duration, logTail: @escaping @Sendable ([String]) -> String) {
        self.helperURL = helperURL
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
            finish(throwing: failure(code: code, message: message))
        case .idle:
            // A job that reaches idle without a result or an error produced nothing.
            finish(throwing: EngineError.generationFailed(detail: ""), idleStillExpected: false)
        default:
            // Results of another kind of helper, and `ready`.
            break
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
            finish(throwing: EngineError.crashed(detail: logTail(recentLog)))
        }
    }

    private func failure(code: String, message: String) -> EngineError {
        if EngineMessage.indicatesOutOfMemory(recentLog) {
            return .outOfMemory
        }
        let tail = logTail(recentLog)
        switch code {
        case "load_failed": return .modelLoadFailed(detail: tail)
        default: return .generationFailed(detail: tail.isEmpty ? message : tail)
        }
    }

    // MARK: - Ending a job

    private func killIfStillRunning(_ id: UUID) {
        guard job?.id == id else { return }
        finish(throwing: CancellationError())
        stopHelper()
    }

    private func finish(throwing error: Error? = nil, idleStillExpected: Bool = true) {
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

    private static func remove(_ files: [URL]) {
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
