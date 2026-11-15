import Foundation

/// Turns text into speech with audio.cpp, through the `kiln-audio` helper process.
public final class AudioCppEngine: InferenceEngine {
    public static let engineID = "audio.cpp"

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
        session = HelperSession(helperURL: helperURL, cancelGracePeriod: cancelGracePeriod) { log in
            log.filter { $0.contains("[error]") }.suffix(3).joined(separator: "\n")
        }
    }

    public func generate(
        recipe: ModelRecipe,
        request: GenerationRequest
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            continuation.onTermination = { [session] reason in
                guard case .cancelled = reason else { return }
                Task { await session.cancel(id) }
            }
            Task { await self.start(id: id, recipe: recipe, request: request, continuation: continuation) }
        }
    }

    public func shutdown() async {
        await session.shutdown()
    }

    private func start(
        id: UUID,
        recipe: ModelRecipe,
        request: GenerationRequest,
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
            let text = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw EngineError.missingText }
            // Only a voice the recipe lists is passed on: some models load a voice
            // from a file named after it.
            let voice = request.speech?.voice ?? recipe.defaultVoice
            if let voice, !recipe.voices.contains(voice) { throw EngineError.unknownVoice(voice) }

            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            let output = scratchDirectory.appendingPathComponent("\(id.uuidString).f32")
            let command = try EngineMessage.speakCommand(
                model: storage.url(for: model), family: family, text: text,
                voice: voice, output: output
            )

            await session.run(id: id, command: command, files: [output], continuation: continuation) { event in
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
