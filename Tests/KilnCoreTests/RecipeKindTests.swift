import Foundation
import Testing
@testable import KilnCore

@Suite struct RecipeKindTests {
    private func decode(output: String?, accepts: String?, defaults: Bool) throws -> ModelRecipe {
        var fields = [
            #""id": "m", "name": "M", "engine": "e""#,
            #""components": [{"role": "checkpoint", "repo": "o/r", "file": "f.gguf"}]"#,
        ]
        if let output { fields.append(#""output": "\#(output)""#) }
        if let accepts { fields.append(#""accepts": \#(accepts)"#) }
        if defaults {
            fields.append(#""defaults": {"steps": 8, "cfg": 1, "sampler": "euler", "width": 64, "height": 64}"#)
        }
        return try RecipeStore.decode(Data("{\(fields.joined(separator: ", "))}".utf8))
    }

    @Test func aRecipeWithoutAKindMakesImagesFromAnImage() throws {
        let recipe = try decode(output: nil, accepts: nil, defaults: true)

        #expect(recipe.outputKind == .image)
        #expect(recipe.inputKinds == [.image])
    }

    @Test func otherKindsTakeNoAttachmentUnlessTheyListOne() throws {
        let speech = try decode(output: "audio", accepts: nil, defaults: false)
        let transcriber = try decode(output: "text", accepts: #"["audio"]"#, defaults: false)
        let textOnlyImages = try decode(output: "image", accepts: "[]", defaults: true)

        #expect(speech.outputKind == .audio)
        #expect(speech.inputKinds.isEmpty)
        #expect(transcriber.inputKinds == [.audio])
        #expect(textOnlyImages.inputKinds.isEmpty)
    }

    @Test func onlyImageModelsNeedImageSettings() throws {
        #expect(throws: RecipeValidationError.missingDefaults) {
            try decode(output: nil, accepts: nil, defaults: false)
        }
        #expect(try decode(output: "text", accepts: #"["audio"]"#, defaults: false).defaults == nil)
    }

    @Test func roundTripsItsKinds() throws {
        let recipe = try decode(output: "text", accepts: #"["audio"]"#, defaults: false)

        #expect(try RecipeStore.decode(JSONEncoder().encode(recipe)) == recipe)
    }

    @Test func anImageModelAlwaysNeedsAPrompt() throws {
        let recipe = try decode(output: nil, accepts: nil, defaults: true)

        #expect(recipe.canRun(prompt: "a fox", hasAttachment: false))
        #expect(!recipe.canRun(prompt: "  \n", hasAttachment: true))
    }

    @Test func aModelThatWorksFromAFileCanRunOnTheFileAlone() throws {
        let transcriber = try decode(output: "text", accepts: #"["audio"]"#, defaults: false)
        let speech = try decode(output: "audio", accepts: nil, defaults: false)

        #expect(transcriber.canRun(prompt: "", hasAttachment: true))
        #expect(!transcriber.canRun(prompt: "", hasAttachment: false))
        #expect(!speech.canRun(prompt: "", hasAttachment: false))
        #expect(speech.canRun(prompt: "Hello", hasAttachment: false))
    }
}
