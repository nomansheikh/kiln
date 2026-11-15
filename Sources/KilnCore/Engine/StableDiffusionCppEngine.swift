import Foundation

/// Makes images with stable-diffusion.cpp, through the `kiln-engine` helper process.
public final class StableDiffusionCppEngine: InferenceEngine {
    public static let engineID = "sd.cpp"

    private let storage: ModelStorage
    private let scratchDirectory: URL
    private let session: HelperSession

    /// - Parameter cancelGracePeriod: How long a cancelled generation may take to stop
    ///   before the helper is killed. Loading a model cannot be interrupted any other way.
    public init(
        helperURL: URL,
        storage: ModelStorage,
        scratchDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-engine"),
        cancelGracePeriod: Duration = .seconds(3)
    ) {
        self.storage = storage
        self.scratchDirectory = scratchDirectory
        session = HelperSession(
            helperURL: helperURL,
            arguments: HelperProcess.sandboxArguments(models: storage.root, scratch: scratchDirectory),
            cancelGracePeriod: cancelGracePeriod
        ) { log in
            let errors = log.filter { $0.contains("[error]") }
            return (errors.isEmpty ? log : errors).suffix(3).joined(separator: "\n")
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
            guard missing.isEmpty else { throw EngineError.missingComponents(missing) }

            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            let output = scratchDirectory.appendingPathComponent("\(id.uuidString).raw")
            let previewFile = scratchDirectory.appendingPathComponent("\(id.uuidString).preview")
            let initFile = try request.writeSourceImage(to: scratchDirectory.appendingPathComponent("\(id.uuidString).init"))
            let command = try EngineMessage.generateCommand(
                recipe: recipe, storage: storage, request: request, output: output, preview: previewFile, initImage: initFile
            )

            await session.run(
                id: id, command: command, files: [output, previewFile] + [initFile].compactMap { $0 },
                continuation: continuation, interpret: Self.interpret
            )
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private static func interpret(_ event: EngineMessage.Event) -> HelperSession.Step? {
        switch event {
        case .preview(let path, let width, let height, let channels):
            // Previews are a nicety: one that cannot be read is skipped.
            GeneratedImage(rawFile: path, width: width, height: height, channels: channels).map { .yield(.preview($0)) }
        case .image(let path, let width, let height, let channels):
            if let image = GeneratedImage(rawFile: path, width: width, height: height, channels: channels) {
                .finish(.image(image))
            } else {
                .fail(.invalidOutput)
            }
        default:
            nil
        }
    }
}
