import Foundation

/// Sends each recipe to the engine its `engine` field names.
///
/// Only one model stays in memory: starting a different engine first shuts
/// down the one used before it.
public actor EngineRouter: InferenceEngine {
    private let engines: [String: any InferenceEngine]
    private var activeID: String?

    /// - Parameter engines: Each engine under the id recipes use for it, such as `sd.cpp`.
    public init(_ engines: [String: any InferenceEngine]) {
        self.engines = engines
    }

    public nonisolated func generate(
        recipe: ModelRecipe,
        request: GenerationRequest
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let engine = try await self.activate(recipe.engine)
                    for try await event in engine.generate(recipe: recipe, request: request) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Cancelling the task ends the inner stream, which cancels the engine's job.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func shutdown() async {
        for engine in engines.values {
            await engine.shutdown()
        }
        activeID = nil
    }

    private func activate(_ id: String) async throws -> any InferenceEngine {
        guard let engine = engines[id] else { throw EngineError.unsupportedEngine(id) }
        if let activeID, activeID != id {
            await engines[activeID]?.shutdown()
        }
        activeID = id
        return engine
    }
}
