import Foundation
import Testing
@testable import KilnCore

/// Drives the real engine class against shell scripts standing in for `kiln-trellis`.
@Suite struct TrellisCppEngineTests {
    let fixture: MeshFixture

    init() throws {
        fixture = try MeshFixture()
    }

    private func run(_ engine: TrellisCppEngine, _ request: GenerationRequest, recipe: ModelRecipe? = nil) async throws -> [GenerationEvent] {
        var events: [GenerationEvent] = []
        for try await event in engine.generate(recipe: recipe ?? fixture.recipe, request: request) { events.append(event) }
        return events
    }

    private var request: GenerationRequest {
        GenerationRequest(prompt: "", attachment: fixture.picture, mesh: MeshSettings(seed: 7))
    }

    private var leftovers: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("scratch").path)) ?? []
    }

    @Test func streamsProgressThenTheObjectAndCleansUp() async throws {
        let engine = try fixture.engine(onShape: fixture.success)

        let events = try await run(engine, request)

        #expect(events == [
            .progress(.init(stage: .building, completed: 12, total: 84)),
            .finished(.mesh(GeneratedMesh(glb: Data("glTF0000000000000000rest".utf8)))),
        ])
        // The picture, the object and the engine's point-cloud copy are all removed.
        #expect(leftovers.isEmpty)
        await engine.shutdown()
    }

    @Test func handsTheHelperAPNGCopyAndTheFolderOfTheModel() async throws {
        // The helper reports the request and the first bytes of the picture instead of an object.
        let engine = try fixture.engine(onShape: """
        head -c 8 "$image" | od -An -tx1 | tr -d ' \\n' > "$output.sig"
        printf '%s' "$line" > "$output.req"
        echo '{"type":"error","code":"generation_failed","message":"stop here"}'
        echo '{"type":"idle"}'
        """)
        await #expect(throws: EngineError.self) { try await run(engine, request) }

        let scratch = fixture.root.appendingPathComponent("scratch")
        let files = try FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)
        let signature = try String(contentsOf: #require(files.first { $0.pathExtension == "sig" }), encoding: .utf8)
        #expect(signature == "89504e470d0a1a0a")
        let sent = try String(contentsOf: #require(files.first { $0.pathExtension == "req" }), encoding: .utf8)
        #expect(sent.contains("\"models\":\"\(fixture.storage.root.path)/owner/name/q4\""))
        #expect(sent.contains("\"resolution\":512") && sent.contains("\"seed\":7") && sent.contains("\"steps\":12"))
        #expect(sent.contains("\"cutout\":\"auto\"") && sent.contains("\"texture_size\":0"))
    }

    @Test func aRequestWithoutAPictureIsRejected() async throws {
        let engine = try fixture.engine(onShape: "echo '{\"type\":\"idle\"}'")
        await #expect(throws: EngineError.missingSourceImage) {
            try await run(engine, GenerationRequest(prompt: "a chair"))
        }
    }

    @Test func aFileThatIsNotAPictureIsRejected() async throws {
        let engine = try fixture.engine(onShape: "echo '{\"type\":\"idle\"}'")
        let file = fixture.root.appendingPathComponent("notes.png")
        try Data("not a picture".utf8).write(to: file)
        await #expect(throws: EngineError.unreadableSourceImage) {
            try await run(engine, GenerationRequest(prompt: "", attachment: file))
        }
    }

    @Test func aModelSpreadOverSeveralFoldersCannotRun() async throws {
        var scattered = fixture.recipe
        scattered.components[1].file = "dinov3.gguf"
        let file = fixture.storage.url(for: scattered.components[1])
        try Data("weights".utf8).write(to: file)
        let engine = try fixture.engine(onShape: fixture.success)

        #expect(engine.modelsFolder(of: scattered) == nil)
        await #expect(throws: EngineError.self) { try await run(engine, request, recipe: scattered) }
    }

    @Test func anObjectThatIsNotAGLBFileIsRefused() async throws {
        let engine = try fixture.engine(onShape: """
        printf 'something else' > "$output"
        echo "{\\"type\\":\\"object\\",\\"path\\":\\"$output\\"}"
        echo '{"type":"idle"}'
        """)
        await #expect(throws: EngineError.invalidOutput) { try await run(engine, request) }
    }

    @Test func aHelperThatEndsWhenToldToStopCountsAsStopped() async throws {
        // The real helper cannot stop part-way, so it says it was stopped and ends.
        let engine = try fixture.engine(onShape: "echo '{\"type\":\"loading\"}'", onCancel: "echo '{\"type\":\"cancelled\"}'; exit 0")
        let task = Task { () -> Bool in
            for try await event in engine.generate(recipe: fixture.recipe, request: request) where event == .loadingModel {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return Task.isCancelled
        }
        #expect(try await task.value)
        // A fresh helper starts for the next object.
        let again = try fixture.engine(onShape: fixture.success)
        #expect(try await run(again, request).last == .finished(.mesh(GeneratedMesh(glb: Data("glTF0000000000000000rest".utf8)))))
    }
}
