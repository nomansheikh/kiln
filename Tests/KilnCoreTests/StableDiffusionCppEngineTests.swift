import Foundation
import Testing
@testable import KilnCore

/// Drives the real engine class against shell scripts standing in for `kiln-engine`.
@Suite struct StableDiffusionCppEngineTests: EngineSuite {
    let fixture: EngineFixture

    init() throws {
        fixture = try EngineFixture()
    }

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

    @Test func streamsStepPreviewsAndCleansThemUp() async throws {
        let engine = try engine(onGenerate: """
        preview=$(printf '%s' "$line" | sed -E 's/.*"preview":"([^"]*)".*/\\1/')
        printf 'abc' > "$preview"
        echo "{\\"type\\":\\"preview\\",\\"path\\":\\"$preview\\",\\"width\\":1,\\"height\\":1,\\"channels\\":3,\\"step\\":1}"
        echo '{"type":"preview","path":"/nonexistent/preview","width":1,"height":1,"channels":3,"step":2}'
        sleep 0.2
        \(success)
        """)

        let events = try await collect(engine.generate(recipe: recipe, request: request))

        // The unreadable second preview is skipped rather than failing the job.
        #expect(events.filter { if case .preview = $0 { true } else { false } }
            == [.preview(GeneratedImage(width: 1, height: 1, channels: 3, pixels: Data("abc".utf8)))])
        #expect(events.last == .finished(GeneratedImage(width: 2, height: 2, channels: 3, pixels: Data("abcdefghijkl".utf8))))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("scratch").path)
        #expect(leftovers.isEmpty)
        await engine.shutdown()
    }

    @Test func handsTheHelperTheSourceImageAtTheOutputSize() async throws {
        // The request is 1024x1024, so the raw RGB file must be 1024 * 1024 * 3 bytes.
        let engine = try engine(onGenerate: """
        init=$(printf '%s' "$line" | sed -E 's/.*"init_image":"([^"]*)".*/\\1/')
        if [ "$(wc -c < "$init" | tr -d ' ')" = "3145728" ]; then
        \(success)
        else
        echo '{"type":"error","code":"invalid_request","message":"wrong source size"}'
        echo '{"type":"idle"}'
        fi
        """)
        let gallery = GalleryStore(directory: root.appendingPathComponent("gallery"))
        let record = GenerationRecord(recipeID: "r", recipeName: "R", request: request)
        let source = try gallery.save(GeneratedImage(width: 3, height: 2, channels: 3, pixels: Data(count: 18)), record: record)
        var edit = request
        edit.sourceImage = source.url
        edit.strength = 0.5

        let events = try await collect(engine.generate(recipe: recipe, request: edit))

        #expect(events.last == .finished(GeneratedImage(width: 2, height: 2, channels: 3, pixels: Data("abcdefghijkl".utf8))))
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
}
