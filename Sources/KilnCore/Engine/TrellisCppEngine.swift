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

    /// The one folder a recipe's files are in, or nil when they are in several.
    func modelsFolder(of recipe: ModelRecipe) -> URL? {
        let folders = Set(recipe.components.map { storage.url(for: $0).deletingLastPathComponent().standardizedFileURL })
        return folders.count == 1 ? folders.first : nil
    }

    /// A folder of links to a recipe's files, for a recipe whose files come from
    /// several repos: the engine opens each file by a fixed name inside one folder.
    /// Nil when two files share a name, so one would hide the other.
    func linkedModelsFolder(of recipe: ModelRecipe, named name: String) throws -> URL? {
        let files = recipe.components.map { storage.url(for: $0) }
        guard Set(files.map(\.lastPathComponent)).count == files.count else { return nil }
        let folder = scratchDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(file.lastPathComponent), withDestinationURL: file)
        }
        return folder
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
            guard let attachment = request.attachment else { throw EngineError.missingSourceImage }

            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            var links: [URL] = []
            var folder = modelsFolder(of: recipe)
            if folder == nil, let linked = try linkedModelsFolder(of: recipe, named: "\(id.uuidString)-models") {
                folder = linked
                links = [linked]
            }
            guard let models = folder else { throw EngineError.missingComponents(["the model's files, each under a name of its own"]) }
            let image = scratchDirectory.appendingPathComponent("\(id.uuidString).png")
            let output = scratchDirectory.appendingPathComponent("\(id.uuidString).glb")
            do {
                try ImageCodec.writePNG(of: attachment, to: image)
            } catch {
                throw EngineError.unreadableSourceImage
            }
            let command = try EngineMessage.shapeCommand(
                models: models, family: recipe.meshFamily, image: image, output: output,
                settings: request.mesh ?? MeshSettings(seed: GenerationRequest.randomSeed())
            )
            // The engine also leaves a point-cloud copy beside the object, which Kiln does not use.
            let leftover = output.deletingPathExtension().appendingPathExtension("ply")

            let lying = recipe.meshFamily == "pixal3d"
            await session.run(id: id, command: command, files: [image, output, leftover] + links, continuation: continuation) { event in
                guard case .object(let path) = event else { return nil }
                guard var glb = try? Data(contentsOf: URL(fileURLWithPath: path)), MeshFile.isGLB(glb) else {
                    return .fail(.invalidOutput)
                }
                if lying {
                    guard let upright = try? GLBUpright.turned(glb) else { return .fail(.invalidOutput) }
                    glb = upright
                }
                return .finish(.mesh(GeneratedMesh(glb: glb)))
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
