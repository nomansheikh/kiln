import Foundation
import Testing
@testable import KilnCore

/// Drives the real engine class against shell scripts standing in for `kiln-audio`.
@Suite struct AudioCppEngineTests {
    let fixture: VoiceFixture

    init() throws {
        fixture = try VoiceFixture()
    }

    private func run(_ engine: AudioCppEngine, _ request: GenerationRequest) async throws -> [GenerationEvent] {
        var events: [GenerationEvent] = []
        for try await event in engine.generate(recipe: fixture.recipe, request: request) { events.append(event) }
        return events
    }

    private var leftovers: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("scratch").path)) ?? []
    }

    @Test func streamsProgressThenTheSound() async throws {
        let engine = try fixture.engine(onSpeak: fixture.success)

        let events = try await run(engine, GenerationRequest(prompt: "Hello there."))

        #expect(events == [
            .loadingModel,
            .progress(.init(stage: .speaking, completed: 0, total: 0)),
            .finished(.audio(GeneratedAudio(sampleRate: 24_000, channels: 1, samples: Data("abcdefgh".utf8)))),
        ])
        #expect(leftovers.isEmpty)
        await engine.shutdown()
    }

    @Test func sendsTheModelItsFamilyTheTextAndTheVoice() async throws {
        // The helper saves the request it was given so the test can read it.
        let seen = fixture.root.appendingPathComponent("request.json")
        let engine = try fixture.engine(onSpeak: "printf '%s' \"$line\" > '\(seen.path)'\n" + fixture.success)

        _ = try await run(engine, GenerationRequest(prompt: "  Hello there.\n", speech: SpeechSettings(voice: "alba")))
        let picked = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: seen)) as? [String: String])
        _ = try await run(engine, GenerationRequest(prompt: "Hello again."))
        let byDefault = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: seen)) as? [String: String])

        #expect(picked["model"] == fixture.storage.url(for: fixture.recipe.components[0]).path)
        #expect(picked["family"] == "pocket_tts")
        #expect(picked["text"] == "Hello there.")
        #expect(picked["voice"] == "alba")
        // Without a choice the recipe's own default voice is used.
        #expect(byDefault["voice"] == "george")
        await engine.shutdown()
    }

    @Test func aVoiceTheRecipeDoesNotListIsRejected() async throws {
        let engine = try fixture.engine(onSpeak: fixture.success)

        await #expect(throws: EngineError.unknownVoice("../../secret")) {
            try await run(engine, GenerationRequest(prompt: "Hello.", speech: SpeechSettings(voice: "../../secret")))
        }
    }

    @Test func aRequestWithoutTextIsRejected() async throws {
        let engine = try fixture.engine(onSpeak: fixture.success)

        await #expect(throws: EngineError.missingText) {
            try await run(engine, GenerationRequest(prompt: " \n"))
        }
    }

    @Test func soundThatDoesNotMatchItsStatedSizeIsRejected() async throws {
        let engine = try fixture.engine(onSpeak: """
        printf 'abc' > "$output"
        echo "{\\"type\\":\\"audio\\",\\"path\\":\\"$output\\",\\"sample_rate\\":24000,\\"channels\\":1,\\"frames\\":2}"
        echo '{"type":"idle"}'
        """)

        await #expect(throws: EngineError.invalidOutput) {
            try await run(engine, GenerationRequest(prompt: "Hello."))
        }
        #expect(leftovers.isEmpty)
        await engine.shutdown()
    }

    @Test func aHelperErrorCarriesTheLibraryExplanation() async throws {
        let engine = try fixture.engine(onSpeak: """
        echo '[error] failed to open safetensors file: nobody.safetensors' >&2
        sleep 0.1
        echo '{"type":"error","code":"generation_failed","message":"The speech could not be generated."}'
        echo '{"type":"idle"}'
        """)

        await #expect(throws: EngineError.generationFailed(detail: "[error] failed to open safetensors file: nobody.safetensors")) {
            try await run(engine, GenerationRequest(prompt: "Hello."))
        }
        await engine.shutdown()
    }
}
