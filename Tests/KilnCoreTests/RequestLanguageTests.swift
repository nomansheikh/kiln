import Foundation
import Testing
@testable import KilnCore

/// The language a user picks reaches the helper only when the recipe offers it.
@Suite struct RequestLanguageTests {
    private func sent(_ file: URL) throws -> [String: String] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String])
    }

    @Test func speechToTextSendsTheChosenLanguageOrAsksForDetection() async throws {
        let fixture = try SpeechFixture()
        var recipe = fixture.recipe
        recipe.languages = ["en", "de"]
        let seen = fixture.root.appendingPathComponent("request.json")
        let engine = try fixture.engine(onTranscribe: """
        printf '%s' "$line" > '\(seen.path)'
        printf '{"segments":[{"start_ms":0,"end_ms":500,"text":"ok"}]}' > "$output"
        echo "{\\"type\\":\\"transcript\\",\\"path\\":\\"$output\\"}"
        echo '{"type":"idle"}'
        """)
        func run(_ language: String?) async throws -> String? {
            for try await _ in engine.generate(recipe: recipe, request: GenerationRequest(prompt: "", attachment: fixture.audio, language: language)) {}
            return try sent(seen)["language"]
        }

        #expect(try await run("de") == "de")
        #expect(try await run(nil) == "auto")
        // A language the model does not list is not passed on.
        #expect(try await run("xx") == "auto")
        await engine.shutdown()
    }

    @Test func textToSpeechSendsALanguageOnlyWhenOneIsChosen() async throws {
        let fixture = try VoiceFixture()
        var recipe = fixture.recipe
        recipe.languages = ["en", "de"]
        let seen = fixture.root.appendingPathComponent("request.json")
        let engine = try fixture.engine(onSpeak: "printf '%s' \"$line\" > '\(seen.path)'\n" + fixture.success)
        func run(_ language: String?) async throws -> String? {
            for try await _ in engine.generate(recipe: recipe, request: GenerationRequest(prompt: "Hallo.", language: language)) {}
            return try sent(seen)["language"]
        }

        #expect(try await run("de") == "de")
        #expect(try await run(nil) == nil)
        #expect(try await run("xx") == nil)
        await engine.shutdown()
    }

    @Test func aRecipeListsLanguageCodesOnce() throws {
        func decode(_ languages: String) throws -> ModelRecipe {
            try RecipeStore.decode(Data("""
            {"id": "m", "name": "M", "engine": "whisper.cpp", "output": "text", "accepts": ["audio"],
             "components": [{"role": "model", "repo": "o/r", "file": "m.bin"}], "languages": \(languages)}
            """.utf8))
        }

        #expect(try decode(#"["en", "zh", "pt-BR", "yue"]"#).languages == ["en", "zh", "pt-BR", "yue"])
        #expect(throws: RecipeValidationError.invalidLanguages) { try decode("[]") }
        #expect(throws: RecipeValidationError.invalidLanguages) { try decode(#"["en", "en"]"#) }
        #expect(throws: RecipeValidationError.invalidLanguages) { try decode(#"["../en"]"#) }
        #expect(throws: RecipeValidationError.invalidLanguages) { try decode(#"["e"]"#) }
    }

    @Test func aRequestKeepsItsLanguageWhenSaved() throws {
        let request = GenerationRequest(prompt: "Hallo.", speech: SpeechSettings(voice: "ryan"), language: "de")

        let decoded = try JSONDecoder().decode(GenerationRequest.self, from: JSONEncoder().encode(request))

        #expect(decoded == request)
    }
}
