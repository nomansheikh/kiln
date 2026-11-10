import Foundation
import Testing
@testable import KilnCore

/// How the engine reports problems: bad requests, crashes and unusable output.
@Suite struct StableDiffusionCppEngineFailureTests: EngineSuite {
    let fixture: EngineFixture

    init() throws {
        fixture = try EngineFixture()
    }

    @Test func anUnreadableSourceImageIsReportedBeforeTheHelperStarts() async throws {
        let engine = try engine(onGenerate: success)
        var edit = request
        edit.sourceImage = root.appendingPathComponent("missing.png")

        await #expect(throws: EngineError.unreadableSourceImage) {
            _ = try await collect(engine.generate(recipe: recipe, request: edit))
        }
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
