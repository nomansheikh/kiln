import Foundation
import Testing
@testable import KilnCore

@Suite struct RecipeSpeechTests {
    private func decode(speech: String?, components: String = #"{"role": "model", "repo": "o/r", "file": "m.gguf"}"#) throws -> ModelRecipe {
        var fields = [
            #""id": "v", "name": "V", "engine": "audio.cpp", "output": "audio""#,
            #""components": [\#(components)]"#,
        ]
        if let speech { fields.append(#""speech": \#(speech)"#) }
        return try RecipeStore.decode(Data("{\(fields.joined(separator: ", "))}".utf8))
    }

    private let twoVoices = """
    {"role": "model", "repo": "o/r", "file": "en/m.gguf"},
    {"role": "voice", "repo": "o/r", "file": "en/embeddings/alba.safetensors"},
    {"role": "voice", "repo": "o/r", "file": "en/embeddings/george.safetensors"}
    """

    @Test func aModelThatMakesAudioNeedsItsFamily() throws {
        #expect(throws: RecipeValidationError.self) { try decode(speech: nil) }
        #expect(throws: RecipeValidationError.self) { try decode(speech: #"{"family": " "}"#) }
        #expect(try decode(speech: #"{"family": "pocket_tts"}"#).task == .textToSpeech)
    }

    @Test func voicesComeFromTheVoiceFilesUnlessTheModelHasItsOwn() throws {
        let fromFiles = try decode(speech: #"{"family": "pocket_tts"}"#, components: twoVoices)
        let builtIn = try decode(speech: #"{"family": "kokoro_tts", "voices": ["af_heart", "bm_george"], "voice": "bm_george"}"#)

        #expect(fromFiles.voices == ["alba", "george"])
        #expect(fromFiles.defaultVoice == "alba")
        #expect(builtIn.voices == ["af_heart", "bm_george"])
        #expect(builtIn.defaultVoice == "bm_george")
    }

    @Test func aDefaultVoiceTheModelDoesNotHaveIsIgnored() throws {
        let recipe = try decode(speech: #"{"family": "pocket_tts", "voice": "nobody"}"#, components: twoVoices)

        #expect(recipe.defaultVoice == "alba")
        #expect(try decode(speech: #"{"family": "pocket_tts"}"#).defaultVoice == nil)
    }

    @Test func onlyVoicesMayRepeatAndNotUnderOneName() throws {
        let sameName = twoVoices + #", {"role": "voice", "repo": "o/r", "file": "other/alba.safetensors"}"#
        let twoModels = twoVoices + #", {"role": "model", "repo": "o/r", "file": "en/second.gguf"}"#

        #expect(throws: RecipeValidationError.duplicateRole(.voice)) { try decode(speech: #"{"family": "pocket_tts"}"#, components: sameName) }
        #expect(throws: RecipeValidationError.duplicateRole(.model)) { try decode(speech: #"{"family": "pocket_tts"}"#, components: twoModels) }
        #expect(throws: RecipeValidationError.self) { try decode(speech: #"{"family": "kokoro_tts", "voices": []}"#) }
    }

    @Test func namesThatCouldPointAtAnotherFileAreRejected() throws {
        #expect(throws: RecipeValidationError.self) { try decode(speech: #"{"family": "../pocket_tts"}"#) }
        #expect(throws: RecipeValidationError.self) { try decode(speech: #"{"family": "kokoro_tts", "voices": ["a/b"]}"#) }
        #expect(throws: RecipeValidationError.self) { try decode(speech: #"{"family": "kokoro_tts", "voices": [".."]}"#) }
    }

    @Test func aVariantKeepsTheSharedVoices() throws {
        var recipe = try decode(speech: #"{"family": "pocket_tts"}"#, components: twoVoices)
        recipe.variants = [.init(id: "q8", name: "Q8", components: [.init(role: .model, repo: "o/r", file: "en/m-q8.gguf")])]

        let resolved = recipe.resolved("q8")

        #expect(resolved.components.map(\.file) == ["en/embeddings/alba.safetensors", "en/embeddings/george.safetensors", "en/m-q8.gguf"])
        #expect(resolved.voices == ["alba", "george"])
        #expect(try JSONDecoder().decode(ModelRecipe.self, from: JSONEncoder().encode(recipe)) == recipe)
    }
}
