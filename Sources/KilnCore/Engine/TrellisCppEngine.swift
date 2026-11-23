import Foundation

/// Makes a 3D object from one image with trellis.cpp, through the `kiln-trellis` helper process.
public final class TrellisCppEngine: InferenceEngine {
    public static let engineID = "trellis.cpp"

    private let storage: ModelStorage
    private let scratchDirectory: URL
    private let session: HelperSession

    public init(
        helperURL: URL,
        storage: ModelStorage,
        scratchDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-trellis"),
        cancelGracePeriod: Duration = .seconds(3)
    ) {
        self.storage = storage
        self.scratchDirectory = scratchDirectory
        session = HelperSession(
            helperURL: helperURL,
            arguments: HelperProcess.sandboxArguments(models: storage.root, scratch: scratchDirectory),
            cancelGracePeriod: cancelGracePeriod
        ) { log in
            log.filter { $0.localizedCaseInsensitiveContains("error") || $0.contains("failed") || $0.hasPrefix("[trellis]") }
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

    /// The one folder a recipe's files are in. The engine opens each file by a
    /// fixed name inside a folder, so a recipe spread over several cannot run.
    func modelsFolder(of recipe: ModelRecipe) -> URL? {
        let folders = Set(recipe.components.map { storage.url(for: $0).deletingLastPathComponent().standardizedFileURL })
        return folders.count == 1 ? folders.first : nil
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
            guard missing.isEmpty, let models = modelsFolder(of: recipe) else {
                throw EngineError.missingComponents(missing.isEmpty ? ["the model's files, in one folder"] : missing)
            }
            guard let attachment = request.attachment else { throw EngineError.missingSourceImage }

            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            let image = scratchDirectory.appendingPathComponent("\(id.uuidString).png")
            let output = scratchDirectory.appendingPathComponent("\(id.uuidString).glb")
            do {
                try ImageCodec.writePNG(of: attachment, to: image)
            } catch {
                throw EngineError.unreadableSourceImage
            }
            let command = try EngineMessage.shapeCommand(
                models: models, image: image, output: output,
                settings: request.mesh ?? MeshSettings(seed: GenerationRequest.randomSeed())
            )
            // The engine also leaves a point-cloud copy beside the object, which Kiln does not use.
            let leftover = output.deletingPathExtension().appendingPathExtension("ply")

            await session.run(id: id, command: command, files: [image, output, leftover], continuation: continuation) { event in
                guard case .object(let path) = event else { return nil }
                guard let glb = try? Data(contentsOf: URL(fileURLWithPath: path)), MeshFile.isGLB(glb) else {
                    return .fail(.invalidOutput)
                }
                return .finish(.mesh(GeneratedMesh(glb: glb)))
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
