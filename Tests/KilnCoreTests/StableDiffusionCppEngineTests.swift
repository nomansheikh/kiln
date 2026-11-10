import Foundation
import Testing
@testable import KilnCore

/// Drives the real engine class against shell scripts standing in for `kiln-engine`.
@Suite struct StableDiffusionCppEngineTests {
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

    /// `body` runs once per generate request, with `$output` set to the requested output path.
    private func engine(onGenerate body: String, onCancel: String = "", grace: Duration = .seconds(3)) throws -> StableDiffusionCppEngine {
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

    private func collect(_ stream: AsyncThrowingStream<GenerationEvent, Error>) async throws -> [GenerationEvent] {
        var events: [GenerationEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    // A 2x2 RGB image is 12 bytes.
    private let success = """
    echo '{"type":"loading"}'
    echo '{"type":"progress","stage":"sampling","completed":1,"total":2}'
    printf 'abcdefghijkl' > "$output"
    echo "{\\"type\\":\\"image\\",\\"path\\":\\"$output\\",\\"width\\":2,\\"height\\":2,\\"channels\\":3}"
    echo '{"type":"idle"}'
    """

    @Test func streamsProgressThenTheImage() async throws {
        let engine = try engine(onGenerate: success)

        let events = try await collect(engine.generate(recipe: recipe, request: request))

        #expect(events == [
            .loadingModel,
            .progress(.init(stage: .sampling, completed: 1, total: 2)),
            .finished(GeneratedImage(width: 2, height: 2, channels: 3, pixels: Data("abcdefghijkl".utf8))),
        ])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("scratch").path)
        #expect(leftovers.isEmpty)
        await engine.shutdown()
    }

    @Test func reusesTheHelperForBackToBackGenerations() async throws {
        let engine = try engine(onGenerate: success)

        for _ in 0..<3 {
            let events = try await collect(engine.generate(recipe: recipe, request: request))
            #expect(events.count == 3)
        }
        await engine.shutdown()
    }

    @Test func reportsMissingFilesWithoutStartingTheHelper() async throws {
        let engine = try engine(onGenerate: success)
        let incomplete = makeRecipe(components: [.init(role: .checkpoint, repo: "owner/other", file: "absent.gguf")])

        await #expect(throws: EngineError.missingComponents(["absent.gguf"])) {
            _ = try await collect(engine.generate(recipe: incomplete, request: request))
        }
    }

    @Test func rejectsRecipesForAnotherEngine() async throws {
        let engine = try engine(onGenerate: success)
        var other = recipe
        other.engine = "mlx"

        await #expect(throws: EngineError.unsupportedEngine("mlx")) {
            _ = try await collect(engine.generate(recipe: other, request: request))
        }
    }

    @Test func aCrashBecomesAnErrorAndTheNextRequestStartsAFreshHelper() async throws {
        let marker = root.appendingPathComponent("crashed-once")
        let engine = try engine(onGenerate: """
        if [ ! -f '\(marker.path)' ]; then
          touch '\(marker.path)'
          echo '[error] metal: unexpected failure' >&2
          exit 134
        fi
        \(success)
        """)

        await #expect(throws: EngineError.crashed(detail: "[error] metal: unexpected failure")) {
            _ = try await collect(engine.generate(recipe: recipe, request: request))
        }

        let events = try await collect(engine.generate(recipe: recipe, request: request))
        #expect(events.count == 3)
        await engine.shutdown()
    }

    @Test func aCrashAfterAnAllocationFailureIsOutOfMemory() async throws {
        let engine = try engine(onGenerate: """
        echo 'ggml_metal_buffer: failed to allocate Metal buffer of 123 bytes (out of memory)' >&2
        exit 134
        """)

        await #expect(throws: EngineError.outOfMemory) {
            _ = try await collect(engine.generate(recipe: recipe, request: request))
        }
    }

    @Test func aLoadFailureCarriesTheEngineLog() async throws {
        let engine = try engine(onGenerate: """
        echo '[error] init model loader from file failed' >&2
        sleep 0.2
        echo '{"type":"error","code":"load_failed","message":"The model could not be loaded."}'
        echo '{"type":"idle"}'
        """)

        await #expect(throws: EngineError.modelLoadFailed(detail: "[error] init model loader from file failed")) {
            _ = try await collect(engine.generate(recipe: recipe, request: request))
        }
        await engine.shutdown()
    }

    @Test func rejectsOutputOfTheWrongSize() async throws {
        let engine = try engine(onGenerate: """
        printf 'short' > "$output"
        echo "{\\"type\\":\\"image\\",\\"path\\":\\"$output\\",\\"width\\":2,\\"height\\":2,\\"channels\\":3}"
        echo '{"type":"idle"}'
        """)

        await #expect(throws: EngineError.invalidOutput) {
            _ = try await collect(engine.generate(recipe: recipe, request: request))
        }
        await engine.shutdown()
    }

    @Test func cancellingTheConsumerCancelsTheGeneration() async throws {
        let engine = try engine(
            onGenerate: "echo '{\"type\":\"loading\"}'",
            onCancel: "echo '{\"type\":\"cancelled\"}'; echo '{\"type\":\"idle\"}'"
        )
        let stream = engine.generate(recipe: recipe, request: request)

        let task = Task {
            var sawLoading = false
            for try await event in stream where event == .loadingModel {
                sawLoading = true
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return sawLoading
        }

        #expect(try await task.value)
        // Once the helper acknowledges the cancel the engine is free again, well
        // before the 3 second grace period after which it would be killed.
        let started = ContinuousClock.now
        let probe = makeRecipe(components: [.init(role: .checkpoint, repo: "owner/other", file: "absent.gguf")])
        var lastError: EngineError? = .busy
        while lastError == .busy, ContinuousClock.now - started < .seconds(2) {
            try await Task.sleep(for: .milliseconds(20))
            do {
                _ = try await collect(engine.generate(recipe: probe, request: request))
            } catch {
                lastError = error as? EngineError
            }
        }
        #expect(lastError == .missingComponents(["absent.gguf"]))
        await engine.shutdown()
    }

    @Test func aHelperThatIgnoresCancelIsKilled() async throws {
        let engine = try engine(onGenerate: "echo '{\"type\":\"loading\"}'; sleep 30", grace: .milliseconds(200))
        let stream = engine.generate(recipe: recipe, request: request)

        let started = ContinuousClock.now
        let task = Task {
            for try await event in stream where event == .loadingModel {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        _ = try? await task.value

        // The engine reports busy until the stuck job was torn down. A recipe with
        // missing files is used as the probe so no second job actually starts.
        let probe = makeRecipe(components: [.init(role: .checkpoint, repo: "owner/other", file: "absent.gguf")])
        var lastError: EngineError? = .busy
        while lastError == .busy, ContinuousClock.now - started < .seconds(5) {
            try await Task.sleep(for: .milliseconds(50))
            do {
                _ = try await collect(engine.generate(recipe: probe, request: request))
            } catch {
                lastError = error as? EngineError
            }
        }
        #expect(lastError == .missingComponents(["absent.gguf"]))
        await engine.shutdown()
    }

    @Test func secondRequestWhileBusyIsRejected() async throws {
        let engine = try engine(onGenerate: "sleep 1; \(success)")
        let first = engine.generate(recipe: recipe, request: request)
        try await Task.sleep(for: .milliseconds(200))

        await #expect(throws: EngineError.busy) {
            _ = try await collect(engine.generate(recipe: recipe, request: request))
        }
        #expect(try await collect(first).count == 3)
        await engine.shutdown()
    }

    @Test func missingHelperIsReportedPlainly() async throws {
        let engine = StableDiffusionCppEngine(helperURL: root.appendingPathComponent("nope"), storage: storage)

        await #expect(throws: EngineError.helperUnavailable("kiln-engine is missing from the app.")) {
            _ = try await collect(engine.generate(recipe: recipe, request: request))
        }
    }
}
