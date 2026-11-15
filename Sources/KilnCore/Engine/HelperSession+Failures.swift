import Foundation

/// How a job ends badly: an error the helper reports, or the helper going away.
extension HelperSession {
    func log(_ line: String, from id: UUID) {
        guard id == launchID else { return }
        recentLog.append(line)
        if recentLog.count > 40 {
            recentLog.removeFirst(recentLog.count - 40)
        }
        // The reason for an error that arrived ahead of it.
        if job?.pendingError != nil, !logTail(recentLog).isEmpty || EngineMessage.indicatesOutOfMemory(recentLog) {
            settleFailure(of: job?.id)
        }
    }

    /// Ends the job with the error the helper reported. The reason is in the
    /// helper's log, which comes through another pipe and can arrive after the
    /// error does, so a failure without one waits a moment for it.
    func fail(code: String, message: String) {
        guard let id = job?.id else { return }
        // The helper's `idle` follows the error and belongs to this job.
        pendingIdleEvents += 1
        job?.pendingError = (code, message)
        if !logTail(recentLog).isEmpty || EngineMessage.indicatesOutOfMemory(recentLog) {
            return settleFailure(of: id)
        }
        Task {
            try? await Task.sleep(for: Self.logWait)
            settleFailure(of: id)
        }
    }

    /// How long an error waits for its reason to be logged.
    private static let logWait: Duration = .milliseconds(750)

    private func settleFailure(of id: UUID?) {
        guard let job, job.id == id, let pending = job.pendingError else { return }
        finish(throwing: failure(code: pending.code, message: pending.message), idleStillExpected: false)
    }

    func helperExited(_ id: UUID) async {
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
}
