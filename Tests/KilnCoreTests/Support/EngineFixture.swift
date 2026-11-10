import Foundation
import Testing
@testable import KilnCore

/// A models folder with one installed recipe, plus fake helpers to run it against.
struct EngineFixture {
    let root: URL
    let storage: ModelStorage
    let recipe: ModelRecipe
    let request: GenerationRequest

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-engine-tests-\(UUID().uuidString)")
        storage = ModelStorage(root: root.appendingPathComponent("models"))
        recipe = makeRecipe(components: [.init(role: .checkpoint, repo: "owner/name", file: "model.safetensors")])
        request = GenerationRequest(prompt: "a cat", defaults: recipe.defaults, seed: 1)

        let model = storage.url(for: recipe.components[0])
        try FileManager.default.createDirectory(at: model.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: model)
    }

    /// A shell script that emits a 2x2 RGB image (12 bytes) the way the real helper does.
    let success = """
    echo '{"type":"loading"}'
    echo '{"type":"progress","stage":"sampling","completed":1,"total":2}'
    printf 'abcdefghijkl' > "$output"
    echo "{\\"type\\":\\"image\\",\\"path\\":\\"$output\\",\\"width\\":2,\\"height\\":2,\\"channels\\":3}"
    echo '{"type":"idle"}'
    """

    /// An engine whose helper is a shell script. `body` runs once per generate
    /// request, with `$line` holding the request and `$output` the output path.
    func engine(onGenerate body: String, onCancel: String = "", grace: Duration = .seconds(3)) throws -> StableDiffusionCppEngine {
        let script = """
        #!/bin/sh
        echo '{"type":"ready","version":"test","commit":"abc"}'
        while IFS= read -r line; do
          case "$line" in
            *'"type":"cancel"'*)
              \(onCancel.isEmpty ? ":" : onCancel)
              ;;
            *'"type":"generate"'*)
              output=$(printf '%s' "$line" | sed -E 's/.*"output":"([^"]*)".*/\\1/')
              \(body)
              ;;
          esac
        done
        """
        let helper = root.appendingPathComponent("helper-\(UUID().uuidString).sh")
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        return StableDiffusionCppEngine(
            helperURL: helper,
            storage: storage,
            scratchDirectory: root.appendingPathComponent("scratch"),
            cancelGracePeriod: grace
        )
    }

    func collect(_ stream: AsyncThrowingStream<GenerationEvent, Error>) async throws -> [GenerationEvent] {
        var events: [GenerationEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }
}

/// Lets a suite use the fixture's members as if they were its own.
protocol EngineSuite {
    var fixture: EngineFixture { get }
}

extension EngineSuite {
    var root: URL { fixture.root }
    var storage: ModelStorage { fixture.storage }
    var recipe: ModelRecipe { fixture.recipe }
    var request: GenerationRequest { fixture.request }
    var success: String { fixture.success }

    func engine(onGenerate body: String, onCancel: String = "", grace: Duration = .seconds(3)) throws -> StableDiffusionCppEngine {
        try fixture.engine(onGenerate: body, onCancel: onCancel, grace: grace)
    }

    func collect(_ stream: AsyncThrowingStream<GenerationEvent, Error>) async throws -> [GenerationEvent] {
        try await fixture.collect(stream)
    }
}
