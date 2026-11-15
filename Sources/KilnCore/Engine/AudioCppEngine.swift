import Foundation

/// Turns text into speech with audio.cpp, through the `kiln-audio` helper process.
///
/// Models run on the GPU. A model that brings the helper down there is run
/// again on the CPU, and stays on the CPU for as long as the app is open:
/// some of audio.cpp's models do not work on Metal yet.
public final class AudioCppEngine: InferenceEngine {
    public static let engineID = "audio.cpp"

    /// The models that failed on the GPU.
    private actor Fallbacks {
        private var recipeIDs: Set<String> = []

        func contains(_ id: String) -> Bool { recipeIDs.contains(id) }
        func insert(_ id: String) { recipeIDs.insert(id) }
    }

    private let fallbacks = Fallbacks()

    private let storage: ModelStorage
    private let scratchDirectory: URL
    private let session: HelperSession

    /// - Parameter cancelGracePeriod: How long a cancelled job may keep running before
    ///   the helper is killed. audio.cpp cannot stop a run in progress, so a job
    ///   that finishes within this time keeps the model loaded.
    public init(
        helperURL: URL,
        storage: ModelStorage,
        scratchDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-audio"),
        cancelGracePeriod: Duration = .seconds(3)
    ) {
        self.storage = storage
        self.scratchDirectory = scratchDirectory
        session = HelperSession(
            helperURL: helperURL,
            arguments: HelperProcess.sandboxArguments(models: storage.root, scratch: scratchDirectory),
            cancelGracePeriod: cancelGracePeriod
        ) { log in
            log.filter { $0.contains("[error]") }.suffix(3).joined(separator: "\n")
        }
    }

    public func generate(
        recipe: ModelRecipe,
        request: GenerationRequest
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let onGPU = await !fallbacks.contains(recipe.id)
                    do {
                        try await forward(attempt(recipe: recipe, request: request, onGPU: onGPU), to: continuation)
                    } catch EngineError.crashed where onGPU {
                        await fallbacks.insert(recipe.id)
                        continuation.yield(.loadingModel)
                        try await forward(attempt(recipe: recipe, request: request, onGPU: false), to: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Cancelling the task ends the attempt's stream, which cancels its job.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func forward(
        _ events: AsyncThrowingStream<GenerationEvent, Error>,
        to continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation
    ) async throws {
        for try await event in events {
            continuation.yield(event)
        }
    }

    /// One run of the request, on the GPU or on the CPU.
    private func attempt(recipe: ModelRecipe, request: GenerationRequest, onGPU: Bool) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            continuation.onTermination = { [session] reason in
                guard case .cancelled = reason else { return }
                Task { await session.cancel(id) }
            }
            Task { await self.start(id: id, recipe: recipe, request: request, onGPU: onGPU, continuation: continuation) }
        }
    }

    public func shutdown() async {
        await session.shutdown()
    }

    private func start(
        id: UUID,
        recipe: ModelRecipe,
        request: GenerationRequest,
        onGPU: Bool,
        continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation
    ) async {
        do {
            guard await !session.isBusy else { throw EngineError.busy }
            guard recipe.engine == Self.engineID else { throw EngineError.unsupportedEngine(recipe.engine) }
            let missing = storage.missingComponents(of: recipe).map(\.file)
            guard missing.isEmpty, let model = recipe.components.first(where: { $0.role == .model }),
                  let family = recipe.speech?.family
            else {
                throw EngineError.missingComponents(missing.isEmpty ? ["the model file"] : missing)
            }
            // Marks such as "[laughs]" reach the model in its own spelling, or not at all.
            let text = SpeechMarks.apply(
                to: request.prompt.trimmingCharacters(in: .whitespacesAndNewlines), tags: recipe.speech?.tags ?? []
            )
            guard !text.isEmpty else { throw EngineError.missingText }
            var direction = try Self.direction(for: request, text: text, recipe: recipe)

            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            let output = scratchDirectory.appendingPathComponent("\(id.uuidString).f32")
            var files = [output]
            var voiceAudio: (file: URL, sampleRate: Int)?
            if let reference = direction.reference {
                let samples = scratchDirectory.appendingPathComponent("\(id.uuidString)-voice.f32")
                try AudioSamples.writeReference(reference, to: samples)
                files.append(samples)
                voiceAudio = (samples, Int(AudioSamples.referenceSampleRate))
            }
            // The voices of several speakers go as sound files, named in one setting.
            for (index, sample) in direction.samples.enumerated() {
                let file = scratchDirectory.appendingPathComponent("\(id.uuidString)-speaker-\(index + 1).wav")
                do {
                    try AudioSamples.referenceClip(of: sample).wavData().write(to: file)
                } catch {
                    throw EngineError.unreadableReference
                }
                files.append(file)
            }
            if !direction.samples.isEmpty {
                direction.options["voice_samples"] = files.suffix(direction.samples.count).map(\.path).joined(separator: ",")
            }
            let command = try EngineMessage.speakCommand(
                model: storage.url(for: model), family: family, text: direction.text, voice: direction.voice, voiceAudio: voiceAudio,
                language: request.language(for: recipe), options: direction.options, onGPU: onGPU, output: output
            )

            await session.run(id: id, command: command, files: files, continuation: continuation) { event in
                guard case .audio(let path, let sampleRate, let channels, let frames) = event else { return nil }
                guard sampleRate > 0, channels > 0, frames > 0,
                      let samples = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      samples.count == frames * channels * MemoryLayout<Float32>.size
                else { return .fail(.invalidOutput) }
                return .finish(.audio(GeneratedAudio(sampleRate: sampleRate, channels: channels, samples: samples)))
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
