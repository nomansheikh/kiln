import Foundation
import KilnCore

/// An engine that answers each request with the events it was given, or waits
/// until released so a test can look at a store while it is busy.
final class FakeEngine: InferenceEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [GenerationEvent] = []
    private var failure: (any Error)?
    private var gate: CheckedContinuation<Void, Never>?
    private var holds = false
    private var received: [(recipe: ModelRecipe, request: GenerationRequest)] = []
    private var shutdowns = 0

    var requests: [GenerationRequest] { lock.withLock { received.map(\.request) } }
    var recipeIDs: [String] { lock.withLock { received.map(\.recipe.id) } }
    var shutdownCount: Int { lock.withLock { shutdowns } }

    /// The events every following request yields, in order.
    func answer(_ events: GenerationEvent...) {
        lock.withLock { script = events; failure = nil }
    }

    func fail(with error: any Error) {
        lock.withLock { failure = error }
    }

    /// Makes requests wait before their events until `release()`.
    func hold() {
        lock.withLock { holds = true }
    }

    func release() {
        lock.withLock {
            holds = false
            defer { gate = nil }
            return gate
        }?.resume()
    }

    func generate(recipe: ModelRecipe, request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        lock.withLock { received.append((recipe, request)) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                await withCheckedContinuation { (waiting: CheckedContinuation<Void, Never>) in
                    let wait = self.lock.withLock {
                        guard self.holds else { return false }
                        self.gate = waiting
                        return true
                    }
                    if !wait { waiting.resume() }
                }
                if Task.isCancelled {
                    return continuation.finish(throwing: CancellationError())
                }
                let (events, failure) = self.lock.withLock { (self.script, self.failure) }
                if let failure {
                    return continuation.finish(throwing: failure)
                }
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
            continuation.onTermination = { reason in
                guard case .cancelled = reason else { return }
                task.cancel()
                self.release()
            }
        }
    }

    func shutdown() async {
        lock.withLock { shutdowns += 1 }
    }
}
