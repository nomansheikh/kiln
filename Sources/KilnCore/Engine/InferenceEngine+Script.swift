import Foundation

extension InferenceEngine {
    /// Reads a text aloud. A script for a model that speaks in one voice at a
    /// time is read turn by turn, each in its speaker's voice, and joined into
    /// one sound; anything else goes to the model as it is. When a later turn
    /// fails, the turns already read are still delivered, followed by the error.
    public func speak(recipe: ModelRecipe, request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        let turns: [GenerationRequest]
        do {
            guard let split = try SpeechCast.turns(of: request, recipe: recipe) else {
                return generate(recipe: recipe, request: request)
            }
            turns = split
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parts: [GeneratedAudio] = []
                    for (index, turn) in turns.enumerated() {
                        do {
                            for try await event in generate(recipe: recipe, request: turn) {
                                switch event {
                                case .finished(.audio(let sound)): parts.append(sound)
                                case .finished: throw EngineError.invalidOutput
                                case .loadingModel where index > 0: break
                                default: continuation.yield(event)
                                }
                            }
                            try Task.checkCancellation()
                        } catch let error where !(error is CancellationError) && !parts.isEmpty {
                            // The lines read so far took time to make, so they are kept
                            // as a clip and the failure names the line that stopped it.
                            if let sound = GeneratedAudio.joined(parts) {
                                continuation.yield(.finished(.audio(sound)))
                            }
                            throw EngineError.scriptStopped(
                                finished: parts.count, total: turns.count,
                                detail: (error as? LocalizedError)?.errorDescription ?? ""
                            )
                        }
                    }
                    guard let sound = GeneratedAudio.joined(parts) else { throw EngineError.invalidOutput }
                    continuation.yield(.finished(.audio(sound)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
