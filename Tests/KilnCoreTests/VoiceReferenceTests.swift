import Foundation
import Testing
@testable import KilnCore

/// Speaking in a voice copied from a recording.
@Suite struct VoiceReferenceTests {
    let fixture: VoiceFixture
    let recording: URL

    init() throws {
        fixture = try VoiceFixture()
        // Two seconds of a tone at 48 kHz.
        let samples = (0..<96_000).map { Float32(sin(Double($0) * 0.05) * 0.4) }
        let sound = GeneratedAudio(sampleRate: 48_000, channels: 1, samples: samples.withUnsafeBufferPointer { Data(buffer: $0) })
        recording = fixture.root.appendingPathComponent("me.wav")
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        try sound.wavData().write(to: recording)
    }

    private func recipe(reference: ModelRecipe.Support?, text: ModelRecipe.Support? = nil) -> ModelRecipe {
        var recipe = fixture.recipe
        recipe.speech?.reference = reference
        recipe.speech?.referenceText = text
        return recipe
    }

    private func request(transcript: String? = nil) -> GenerationRequest {
        GenerationRequest(prompt: "Hello.", speech: SpeechSettings(voice: "alba", reference: VoiceReference(file: recording, transcript: transcript)))
    }

    @Test func aRecordingTakesThePlaceOfANamedVoice() throws {
        let direction = try AudioCppEngine.direction(for: request(transcript: " Hi there. "), recipe: recipe(reference: .optional, text: .optional))

        #expect(direction == .init(voice: nil, reference: recording, text: "Hello.", options: ["reference_text": "Hi there."]))
    }

    @Test func aModelThatCannotCopyAVoiceKeepsItsOwn() throws {
        let direction = try AudioCppEngine.direction(for: request(transcript: "Hi"), recipe: recipe(reference: nil))

        #expect(direction == .init(voice: "alba", text: "Hello."))
    }

    @Test func theWordsGoOnlyToAModelThatTakesThem() throws {
        #expect(try AudioCppEngine.direction(for: request(transcript: "Hi"), recipe: recipe(reference: .optional)).options.isEmpty)
        #expect(throws: EngineError.missingReferenceText) {
            try AudioCppEngine.direction(for: request(), recipe: recipe(reference: .optional, text: .required))
        }
    }

    @Test func aModelThatOnlyCopiesVoicesSaysSoWithoutOne() {
        #expect(throws: EngineError.missingReference) {
            try AudioCppEngine.direction(for: GenerationRequest(prompt: "Hello."), recipe: recipe(reference: .required))
        }
    }

    @Test func theHelperIsGivenTheRecordingAsSamplesAndCleansUpAfter() async throws {
        let seen = fixture.root.appendingPathComponent("request.json")
        let size = fixture.root.appendingPathComponent("size")
        let body = """
        printf '%s' "$line" > '\(seen.path)'
        voice=$(printf '%s' "$line" | sed -E 's/.*"voice_audio":"([^"]*)".*/\\1/')
        wc -c < "$voice" | tr -d ' \\n' > '\(size.path)'

        """
        let engine = try fixture.engine(onSpeak: body + fixture.success)
        for try await _ in engine.generate(recipe: recipe(reference: .optional), request: request()) {}
        await engine.shutdown()

        let sent = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: seen)) as? [String: Any])
        #expect(sent["voice"] == nil)
        #expect(sent["voice_sample_rate"] as? Int == 24_000)
        // Two seconds, resampled to 24 kHz, four bytes a sample.
        let bytes = try #require(Int(String(contentsOf: size, encoding: .utf8)))
        #expect(abs(bytes - 192_000) < 2_000)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("scratch").path)) ?? []
        #expect(left.isEmpty)
    }

    @Test func onlyTheStartOfALongRecordingIsUsed() throws {
        let samples = [Float32](repeating: 0.2, count: 16_000 * 40)
        let long = fixture.root.appendingPathComponent("long.wav")
        try GeneratedAudio(sampleRate: 16_000, channels: 1, samples: samples.withUnsafeBufferPointer { Data(buffer: $0) })
            .wavData().write(to: long)

        let clip = try AudioSamples.referenceClip(of: long)

        #expect(clip.sampleRate == 24_000)
        #expect(abs(clip.durationSeconds - AudioSamples.referenceSeconds) < 0.01)
        #expect(abs(try AudioSamples.referenceClip(of: recording).durationSeconds - 2) < 0.05)
    }

    @Test func aRecordingThatCannotBeReadIsNamedAsSuch() async throws {
        let engine = try fixture.engine(onSpeak: fixture.success)
        let broken = GenerationRequest(prompt: "Hello.", speech: SpeechSettings(reference: VoiceReference(file: fixture.root.appendingPathComponent("none.wav"))))

        await #expect(throws: EngineError.unreadableReference) {
            for try await _ in engine.generate(recipe: recipe(reference: .optional), request: broken) {}
        }
        await engine.shutdown()
    }

    @Test func aRecipeSaysWhetherItsModelCopiesVoices() throws {
        func decode(_ speech: String) throws -> ModelRecipe {
            try RecipeStore.decode(Data("""
            {"id": "v", "name": "V", "engine": "audio.cpp", "output": "audio", "speech": \(speech),
             "components": [{"role": "model", "repo": "o/r", "file": "m.gguf"}]}
            """.utf8))
        }
        let copies = try decode(#"{"family": "f5_tts", "reference": "required", "reference_text": "required"}"#)

        #expect(copies.speech?.reference == .required)
        #expect(copies.speech?.referenceText == .required)
        #expect(try decode(#"{"family": "pocket_tts", "voices": ["a"]}"#).speech?.reference == nil)
        #expect(throws: RecipeValidationError.self) { try decode(#"{"family": "f", "reference_text": "optional"}"#) }
    }
}
