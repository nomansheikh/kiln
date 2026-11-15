import Foundation
@testable import KilnCore

/// Replies to every request with fixed events and records what it was asked to do.
final class FakeEngine: InferenceEngine, @unchecked Sendable {
    private let lock = NSLock()
    private let events: [GenerationEvent]
    private var generated: [String] = []
    private var requests: [GenerationRequest] = []
    private var shutdowns = 0

    /// The request, counted from 1, that fails instead of replying, and what it fails with.
    private let failure: (request: Int, error: EngineError)?

    init(events: [GenerationEvent] = [], failingOn failure: (request: Int, error: EngineError)? = nil) {
        self.events = events
        self.failure = failure
    }

    /// Ids of the recipes it generated with, in order.
    var generatedRecipeIDs: [String] { lock.withLock { generated } }
    /// The requests it was given, in order.
    var generatedRequests: [GenerationRequest] { lock.withLock { requests } }
    var shutdownCount: Int { lock.withLock { shutdowns } }

    func generate(recipe: ModelRecipe, request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        lock.withLock {
            generated.append(recipe.id)
            requests.append(request)
        }
        let count = lock.withLock { requests.count }
        if let failure, failure.request == count {
            return AsyncThrowingStream { $0.finish(throwing: failure.error) }
        }
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func shutdown() async {
        lock.withLock { shutdowns += 1 }
    }
}
