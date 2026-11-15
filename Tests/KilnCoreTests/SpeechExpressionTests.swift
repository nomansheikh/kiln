import Foundation
import Testing
@testable import KilnCore

/// A model's expression controls: a description of the voice or the delivery,
/// and the marks it understands inside the text.
@Suite struct SpeechExpressionTests {
    let fixture: VoiceFixture

    init() throws {
        fixture = try VoiceFixture()
    }

    private func decode(speech: String) throws -> ModelRecipe {
        try RecipeStore.decode(Data("""
        {"id": "v", "name": "V", "engine": "audio.cpp", "output": "audio", "speech": \(speech),
         "components": [{"role": "model", "repo": "o/r", "file": "m.gguf"}]}
        """.utf8))
    }

    /// Runs one request and returns what the helper was sent.
    private func sent(_ instruction: ModelRecipe.Support?, _ settings: SpeechSettings) async throws -> [String: Any] {
        let seen = fixture.root.appendingPathComponent("request.json")
        let engine = try fixture.engine(onSpeak: "printf '%s' \"$line\" > '\(seen.path)'\n" + fixture.success)
        var recipe = fixture.recipe
        recipe.speech?.instruction = instruction
        for try await _ in engine.generate(recipe: recipe, request: GenerationRequest(prompt: "Hello.", speech: settings)) {}
        await engine.shutdown()
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: seen)) as? [String: Any])
    }

    @Test func aRecipeSaysWhatItsModelAccepts() throws {
        let plain = try decode(speech: #"{"family": "pocket_tts", "voices": ["a"]}"#)
        let expressive = try decode(speech: ##"{"family": "omnivoice", "instruction": "optional", "tags": ["[laughter]", "<sigh>"]}"##)

        #expect(plain.speech?.instruction == nil)
        #expect(plain.speech?.tags == nil)
        #expect(expressive.speech?.instruction == .optional)
        #expect(expressive.speech?.tags == ["[laughter]", "<sigh>"])
        #expect(try decode(speech: #"{"family": "maya1", "instruction": "required"}"#).speech?.instruction == .required)
    }

    @Test func tagsMustBeShortSingleLinesListedOnce() {
        for tags in [#"[]"#, #"["[sigh]", "[sigh]"]"#, #"[""]"#, #"[" [sigh]"]"#, #"["[a]\n[b]"]"#, "[\"\(String(repeating: "x", count: 41))\"]"] {
            #expect(throws: RecipeValidationError.self) { try decode(speech: #"{"family": "f", "tags": \#(tags)}"#) }
        }
        #expect(throws: (any Error).self) { try decode(speech: #"{"family": "f", "instruction": "sometimes"}"#) }
    }

    @Test func anInstructionGoesOnlyToAModelThatTakesOne() async throws {
        let taken = try await sent(.optional, SpeechSettings(instruction: "  Very happy.\n"))
        let refused = try await sent(nil, SpeechSettings(instruction: "Very happy."))
        let empty = try await sent(.optional, SpeechSettings(instruction: "  "))

        #expect(taken["options"] as? [String: String] == ["instruct": "Very happy."])
        #expect(refused["options"] == nil)
        #expect(empty["options"] == nil)
    }

    @Test func fixedStyleWordsAreOneFromEachGroup() async throws {
        let recipe = try decode(speech: """
        {"family": "omnivoice", "styles": [{"name": "Gender", "options": ["male", "female"]},
                                           {"name": "Age", "options": ["child", "elderly"]}]}
        """)
        let speech = try #require(recipe.speech)

        #expect(speech.instruction(choosing: ["elderly", "female"]) == "female, elderly")
        #expect(speech.instruction(choosing: ["male", "female", "very happy"]) == "male")
        #expect(speech.instruction(choosing: []) == nil)

        for styles in [
            #"[]"#, #"[{"name": "Age", "options": []}]"#, #"[{"name": "", "options": ["a"]}]"#,
            #"[{"name": "Age", "options": ["a, b"]}]"#, #"[{"name": "A", "options": ["x"]}, {"name": "B", "options": ["x"]}]"#,
        ] {
            #expect(throws: RecipeValidationError.self) { try decode(speech: #"{"family": "f", "styles": \#(styles)}"#) }
        }
        #expect(throws: RecipeValidationError.self) {
            try decode(speech: #"{"family": "f", "instruction": "optional", "styles": [{"name": "Age", "options": ["child"]}]}"#)
        }
    }

    @Test func aModelWithFixedStyleWordsIsSentOnlyTheOnesItKnows() async throws {
        let seen = fixture.root.appendingPathComponent("request.json")
        let engine = try fixture.engine(onSpeak: "printf '%s' \"$line\" > '\(seen.path)'\n" + fixture.success)
        var recipe = fixture.recipe
        recipe.speech?.styles = [.init(name: "Gender", options: ["male", "female"]), .init(name: "Pitch", options: ["low pitch"])]
        let request = GenerationRequest(prompt: "Hello.", speech: SpeechSettings(instruction: "low pitch, very happy, female"))
        for try await _ in engine.generate(recipe: recipe, request: request) {}
        await engine.shutdown()

        let sent = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: seen)) as? [String: Any])
        #expect(sent["options"] as? [String: String] == ["instruct": "female, low pitch"])
    }

    @Test func marksInTheTextReachTheModelInItsOwnSpellingOrNotAtAll() async throws {
        let seen = fixture.root.appendingPathComponent("request.json")
        let engine = try fixture.engine(onSpeak: "printf '%s' \"$line\" > '\(seen.path)'\n" + fixture.success)
        var withTags = fixture.recipe
        withTags.speech?.tags = ["[laughter]"]
        func text(_ recipe: ModelRecipe) async throws -> String? {
            for try await _ in engine.generate(recipe: recipe, request: GenerationRequest(prompt: "Well [laughs] it worked [sigh].")) {}
            return try (JSONSerialization.jsonObject(with: Data(contentsOf: seen)) as? [String: Any])?["text"] as? String
        }

        #expect(try await text(withTags) == "Well [laughter] it worked.")
        #expect(try await text(fixture.recipe) == "Well it worked.")
        // Nothing but a mark the model lacks leaves nothing to say.
        await #expect(throws: EngineError.missingText) {
            for try await _ in engine.generate(recipe: fixture.recipe, request: GenerationRequest(prompt: "[laughs]")) {}
        }
        await engine.shutdown()
    }

    @Test func aModelThatNeedsAnInstructionSaysSoWithoutOne() async throws {
        await #expect(throws: EngineError.missingInstruction) { _ = try await sent(.required, SpeechSettings()) }
        #expect(try await sent(.required, SpeechSettings(instruction: "A warm narrator"))["options"] as? [String: String]
            == ["instruct": "A warm narrator"])
    }

    @Test func aClipRemembersItsInstruction() throws {
        let request = GenerationRequest(prompt: "Hi", speech: SpeechSettings(voice: "ryan", instruction: "Whispering"))
        let decoded = try JSONDecoder().decode(GenerationRequest.self, from: JSONEncoder().encode(request))

        #expect(decoded.speech?.instruction == "Whispering")
        // A clip saved before instructions existed still loads.
        let old = try JSONDecoder().decode(SpeechSettings.self, from: Data(#"{"voice": "ryan"}"#.utf8))
        #expect(old == SpeechSettings(voice: "ryan"))
    }
}
