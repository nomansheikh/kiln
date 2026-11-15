import Foundation

/// Turns speech into text with whisper.cpp, through the `kiln-whisper` helper process.
public final class WhisperCppEngine: InferenceEngine {
    public static let engineID = "whisper.cpp"

    private let storage: ModelStorage
    private let scratchDirectory: URL
    private let session: HelperSession

    public init(
        helperURL: URL,
        storage: ModelStorage,
        scratchDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-whisper"),
        cancelGracePeriod: Duration = .seconds(3)
    ) {
        self.storage = storage
        self.scratchDirectory = scratchDirectory
        session = HelperSession(helperURL: helperURL, cancelGracePeriod: cancelGracePeriod) { log in
            log.filter { $0.localizedCaseInsensitiveContains("error") || $0.contains("failed") }
                .suffix(3).joined(separator: "\n")
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
            guard missing.isEmpty, let model = recipe.components.first(where: { $0.role == .model }) else {
                throw EngineError.missingComponents(missing.isEmpty ? ["the model file"] : missing)
            }
            guard let attachment = request.attachment else { throw EngineError.missingAudio }

            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            let audio = scratchDirectory.appendingPathComponent("\(id.uuidString).f32")
            let output = scratchDirectory.appendingPathComponent("\(id.uuidString).txt")
            try AudioSamples.write(attachment, to: audio)
            let command = try EngineMessage.transcribeCommand(
                model: storage.url(for: model), audio: audio, prompt: request.prompt,
                language: request.language(for: recipe), output: output
            )

            await session.run(id: id, command: command, files: [audio, output], continuation: continuation) { event in
                guard case .text(let path) = event else { return nil }
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return .fail(.invalidOutput) }
                return .finish(.text(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
