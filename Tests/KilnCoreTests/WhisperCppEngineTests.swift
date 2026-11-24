import Foundation
import Testing
@testable import KilnCore

/// Drives the real engine class against shell scripts standing in for `kiln-whisper`.
@Suite struct WhisperCppEngineTests {
    let fixture: SpeechFixture

    init() throws {
        fixture = try SpeechFixture()
    }

    private func run(_ engine: WhisperCppEngine, _ request: GenerationRequest) async throws -> [GenerationEvent] {
        var events: [GenerationEvent] = []
        for try await event in engine.generate(recipe: fixture.recipe, request: request) { events.append(event) }
        return events
    }

    private var leftovers: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("scratch").path)) ?? []
    }

    @Test func streamsProgressThenTheTranscript() async throws {
        let engine = try fixture.engine(onTranscribe: """
        echo '{"type":"loading"}'
        echo '{"type":"progress","stage":"transcribing","completed":50,"total":100}'
        echo '{"type":"segment","start_ms":0,"end_ms":1500,"text":"  Hello there."}'
        printf '{"segments":[{"start_ms":0,"end_ms":1500,"text":"  Hello there."},{"start_ms":1500,"end_ms":3200,"text":" How are you?"}]}' > "$output"
        echo "{\\"type\\":\\"transcript\\",\\"path\\":\\"$output\\"}"
        echo '{"type":"idle"}'
        """)

        let events = try await run(engine, GenerationRequest(prompt: "", attachment: fixture.audio))

        #expect(events == [
            .loadingModel,
            .progress(.init(stage: .transcribing, completed: 50, total: 100)),
            .segment(.init(start: 0, end: 1.5, text: "  Hello there.")),
            .finished(.transcript(Transcript(segments: [
                .init(start: 0, end: 1.5, text: "Hello there."),
                .init(start: 1.5, end: 3.2, text: "How are you?"),
            ]))),
        ])
        #expect(leftovers.isEmpty)
        await engine.shutdown()
    }

    @Test func aResultThatIsNotATranscriptFailsTheJob() async throws {
        let engine = try fixture.engine(onTranscribe: """
        printf 'Hello there.' > "$output"
        echo "{\\"type\\":\\"transcript\\",\\"path\\":\\"$output\\"}"
        echo '{"type":"idle"}'
        """)

        await #expect(throws: EngineError.invalidOutput) {
            try await run(engine, GenerationRequest(prompt: "", attachment: fixture.audio))
        }
        await engine.shutdown()
    }

    @Test func handsTheHelperSixteenKilohertzMonoSamples() async throws {
        // The helper reports the size of the samples file as the transcript.
        let engine = try fixture.engine(onTranscribe: """
        printf '{"segments":[{"start_ms":0,"end_ms":1000,"text":"%s"}]}' "$(wc -c < "$audio" | tr -d ' \\n')" > "$output"
        echo "{\\"type\\":\\"transcript\\",\\"path\\":\\"$output\\"}"
        echo '{"type":"idle"}'
        """)

        let events = try await run(engine, GenerationRequest(prompt: "", attachment: fixture.audio))

        guard case .finished(.transcript(let size)) = events.last, let bytes = Int(size.text) else {
            Issue.record("no transcript: \(events)")
            return
        }
        // One second of audio is 16 000 four-byte samples, give or take the resampler's edges.
        #expect(abs(bytes / 4 - 16_000) < 200)
        #expect(bytes % 4 == 0)
        await engine.shutdown()
    }

    @Test func aRequestWithoutAudioIsRejected() async throws {
        let engine = try fixture.engine(onTranscribe: "echo '{\"type\":\"idle\"}'")

        await #expect(throws: EngineError.missingAudio) {
            try await run(engine, GenerationRequest(prompt: "hello"))
        }
    }

    @Test func aFileThatIsNotAudioIsRejected() async throws {
        let engine = try fixture.engine(onTranscribe: "echo '{\"type\":\"idle\"}'")
        let file = fixture.root.appendingPathComponent("notes.wav")
        try Data("not audio".utf8).write(to: file)

        await #expect(throws: EngineError.unreadableAudio) {
            try await run(engine, GenerationRequest(prompt: "", attachment: file))
        }
        #expect(leftovers.isEmpty)
    }

    @Test func aHelperErrorFailsTheRequestAndCleansUp() async throws {
        let engine = try fixture.engine(onTranscribe: """
        echo '{"type":"error","code":"generation_failed","message":"The audio could not be transcribed."}'
        echo '{"type":"idle"}'
        """)

        await #expect(throws: EngineError.generationFailed(detail: "The audio could not be transcribed.")) {
            try await run(engine, GenerationRequest(prompt: "", attachment: fixture.audio))
        }
        #expect(leftovers.isEmpty)
        await engine.shutdown()
    }

    @Test func aCrashedHelperIsReportedAndReplaced() async throws {
        let marker = fixture.root.appendingPathComponent("crashed-once")
        let engine = try fixture.engine(onTranscribe: """
        if [ ! -f "\(marker.path)" ]; then touch "\(marker.path)"; exit 1; fi
        printf '{"segments":[{"start_ms":0,"end_ms":900,"text":"Second try."}]}' > "$output"
        echo "{\\"type\\":\\"transcript\\",\\"path\\":\\"$output\\"}"
        echo '{"type":"idle"}'
        """)
        let request = GenerationRequest(prompt: "", attachment: fixture.audio)

        await #expect(throws: EngineError.crashed(detail: "")) { try await run(engine, request) }
        #expect(try await run(engine, request).last == .finished(.transcript(Transcript(segments: [.init(start: 0, end: 0.9, text: "Second try.")]))))
        await engine.shutdown()
    }
}
