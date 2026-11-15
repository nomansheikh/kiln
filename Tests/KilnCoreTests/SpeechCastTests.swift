import Foundation
import Testing
@testable import KilnCore

/// Reading a script with a model that speaks in one voice at a time.
@Suite struct SpeechCastTests {
    private let script = "Anna: Hi.\nBen (grumpy): Yo.\nAnna: Bye."

    /// A model with the named voices "alba" and "george", of which "george" is the default.
    private func named() throws -> ModelRecipe {
        try VoiceFixture().recipe
    }

    /// A model without voices of its own that copies them from recordings.
    private func copying() throws -> ModelRecipe {
        var recipe = try VoiceFixture().recipe
        recipe.components.removeAll { $0.role == .voice }
        recipe.speech = .init(family: "omnivoice", reference: .optional)
        return recipe
    }

    private func recording(_ name: String) -> VoiceReference {
        VoiceReference(file: URL(fileURLWithPath: "/voices/\(name).wav"), transcript: "Words.", name: name)
    }

    private func tone(_ frames: Int, rate: Int = 24_000) -> GeneratedAudio {
        let samples = [Float32](repeating: 0.5, count: frames)
        return GeneratedAudio(sampleRate: rate, channels: 1, samples: samples.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    @Test func speakersTakeTheModelsVoicesInTurn() throws {
        let voices = SpeechCast.voices(for: SpeechScript(script), recipe: try named(), settings: nil)
        #expect(voices == ["anna": CastVoice(voice: "george"), "ben": CastVoice(voice: "alba")])
    }

    @Test func aChosenVoiceIsKeptAndNotGivenTwice() throws {
        let settings = SpeechSettings(cast: ["Ben": CastVoice(voice: "george"), "Anna": CastVoice(voice: "nobody")])
        let voices = SpeechCast.voices(for: SpeechScript(script), recipe: try named(), settings: settings)
        #expect(voices == ["anna": CastVoice(voice: "alba"), "ben": CastVoice(voice: "george")])
    }

    @Test func aSpeakerNamedLikeAVoiceGetsThatVoice() throws {
        let voices = SpeechCast.voices(for: SpeechScript("Tom: Hi.\nAlba: Yo."), recipe: try named(), settings: nil)
        #expect(voices == ["tom": CastVoice(voice: "george"), "alba": CastVoice(voice: "alba")])
    }

    @Test func aScriptBecomesOneRequestPerTurn() throws {
        let request = GenerationRequest(prompt: script, speech: SpeechSettings(instruction: "calm"), language: "en")
        var recipe = try named()
        recipe.speech?.instruction = .optional
        let turns = try #require(try SpeechCast.turns(of: request, recipe: recipe))
        #expect(turns.map(\.prompt) == ["Hi.", "Yo.", "Bye."])
        #expect(turns.map { $0.speech?.voice } == ["george", "alba", "george"])
        #expect(turns.map { $0.speech?.instruction } == ["calm", "grumpy", "calm"])
        #expect(turns.allSatisfy { $0.language == "en" })
    }

    @Test func aTurnsNoteJoinsTheStyleWordsOfAModelWithFixedOnes() throws {
        var recipe = try named()
        recipe.speech?.styles = [.init(name: "Manner", options: ["whisper"])]
        let request = GenerationRequest(prompt: "A (whisper): Hi.\nB: Yo.", speech: SpeechSettings(instruction: "male"))
        let turns = try #require(try SpeechCast.turns(of: request, recipe: recipe))
        #expect(turns.map { $0.speech?.instruction } == ["male, whisper", "male"])
    }

    @Test func oneSpeakerOrAModelThatReadsScriptsIsLeftWhole() throws {
        #expect(try SpeechCast.turns(of: GenerationRequest(prompt: "Anna: Hi there."), recipe: try named()) == nil)
        var reads = try named()
        reads.speech?.speakers = .init(max: 4, line: "Speaker {n}: {text}")
        #expect(try SpeechCast.turns(of: GenerationRequest(prompt: script), recipe: reads) == nil)
    }

    @Test func aCopyingModelNeedsAVoiceForEverySpeaker() throws {
        let recipe = try copying()
        let settings = SpeechSettings(cast: ["Anna": CastVoice(reference: recording("a"))])
        #expect(SpeechCast.speakersWithoutVoice(in: SpeechScript(script), recipe: recipe, settings: settings) == ["Ben"])
        #expect(throws: EngineError.missingSpeakerVoice("Ben")) {
            try SpeechCast.turns(of: GenerationRequest(prompt: self.script, speech: settings), recipe: recipe)
        }
        let full = SpeechSettings(cast: ["Anna": CastVoice(reference: recording("a")), "ben": CastVoice(reference: recording("b"))])
        let turns = try #require(try SpeechCast.turns(of: GenerationRequest(prompt: script, speech: full), recipe: recipe))
        #expect(turns.map { $0.speech?.reference?.name } == ["a", "b", "a"])
        #expect(turns.allSatisfy { $0.speech?.voice == nil })
    }

    @Test func soundsAreJoinedWithAPauseBetweenThem() throws {
        let joined = try #require(GeneratedAudio.joined([tone(100), tone(50)], gapSeconds: 0.5))
        #expect(joined.frameCount == 100 + 12_000 + 50)
        #expect(GeneratedAudio.joined([]) == nil)
        #expect(GeneratedAudio.joined([tone(10), tone(10, rate: 16_000)]) == nil)
    }

    @Test func aScriptIsReadTurnByTurnAndComesBackAsOneSound() async throws {
        let engine = FakeEngine(events: [.loadingModel, .finished(.audio(tone(100)))])
        var events: [GenerationEvent] = []
        for try await event in engine.speak(recipe: try named(), request: GenerationRequest(prompt: script)) {
            events.append(event)
        }
        #expect(engine.generatedRequests.map(\.prompt) == ["Hi.", "Yo.", "Bye."])
        let gap = 6_000
        // The model is loaded once, however many turns there are.
        #expect(events.count == 2 && events.first == .loadingModel)
        guard case .finished(.audio(let sound)) = events.last else {
            Issue.record("no sound")
            return
        }
        #expect(sound.frameCount == 300 + 2 * gap)
    }

    @Test func aLineThatFailsKeepsTheLinesReadBeforeIt() async throws {
        let engine = FakeEngine(
            events: [.finished(.audio(tone(100)))], failingOn: (request: 3, error: .generationFailed(detail: "out of words"))
        )
        var events: [GenerationEvent] = []
        var failure: Error?
        do {
            for try await event in engine.speak(recipe: try named(), request: GenerationRequest(prompt: script)) {
                events.append(event)
            }
        } catch {
            failure = error
        }
        // The first two lines arrive as a clip, then the error names the third.
        guard events.count == 1, case .finished(.audio(let clip)) = events[0] else {
            Issue.record("expected one clip, got \(events)")
            return
        }
        #expect(clip.frameCount == 100 + 6_000 + 100)
        guard case .scriptStopped(finished: 2, total: 3, let detail) = failure as? EngineError else {
            Issue.record("unexpected failure: \(String(describing: failure))")
            return
        }
        #expect(detail.contains("out of words"))
    }

    @Test func aFirstLineThatFailsFailsAsItDid() async throws {
        let engine = FakeEngine(events: [.finished(.audio(tone(100)))], failingOn: (request: 1, error: .missingText))
        await #expect(throws: EngineError.missingText) {
            for try await _ in engine.speak(recipe: try self.named(), request: GenerationRequest(prompt: self.script)) {}
        }
    }

    @Test func plainTextGoesToTheModelAsItIs() async throws {
        let engine = FakeEngine(events: [.finished(.audio(tone(100)))])
        for try await _ in engine.speak(recipe: try named(), request: GenerationRequest(prompt: "Hello there.")) {}
        #expect(engine.generatedRequests.map(\.prompt) == ["Hello there."])
    }

    @Test func aDesignedVoiceKeepsItsDescription() throws {
        let fixture = try VoiceFixture()
        let file = fixture.root.appendingPathComponent("made.wav")
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        try tone(24_000).wavData().write(to: file)
        let store = VoiceStore(directory: fixture.root.appendingPathComponent("voices"))
        try store.add(recording: file, name: "Narrator", transcript: "Words.", design: "female, elderly")
        #expect(store.voices().map(\.design) == ["female, elderly"])
    }
}
