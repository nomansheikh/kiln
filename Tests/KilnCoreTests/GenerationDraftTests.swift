import Foundation
import Testing
@testable import KilnCore

/// What the Generate composer sends, and what switching the model changes.
@Suite struct GenerationDraftTests {
    private let speech = SpeechDraftFixture()

    private func image(steps: Int = 8, sigmas: [Double]? = nil) -> ModelRecipe {
        makeRecipe(defaults: .init(steps: steps, cfg: 1, sampler: "lcm", width: 768, height: 512, sigmas: sigmas))
    }

    private var transcriber: ModelRecipe {
        var recipe = ModelRecipe(
            id: "whisper", name: "Whisper", engine: "whisper.cpp",
            components: [.init(role: .model, repo: "o/r", file: "ggml.bin")],
            output: .text, accepts: [.audio], defaults: nil
        )
        recipe.languages = ["en", "de"]
        return recipe
    }

    // MARK: - Switching the model

    @Test func selectingAModelAppliesItsSettingsAndKeepsThePrompt() {
        var draft = GenerationDraft()
        draft.prompt = "A fox."
        draft.select(image())
        #expect(draft.recipeID == "test-model")
        #expect(draft.width == 768 && draft.height == 512 && draft.steps == 8)
        #expect(draft.cfg == 1)
        #expect(draft.sampler == "lcm")
        #expect(draft.prompt == "A fox.")
    }

    @Test func aModelWithoutImageSettingsLeavesThemAlone() {
        var draft = GenerationDraft()
        draft.select(image())
        draft.select(transcriber)
        #expect(draft.recipeID == "whisper")
        #expect(draft.steps == 8)
    }

    @Test func theVoiceAndLanguageFollowWhatTheNewModelOffers() {
        var draft = GenerationDraft()
        draft.select(speech.named)
        #expect(draft.voice == "george")

        draft.voice = "alba"
        draft.select(speech.described(.optional))
        #expect(draft.voice == "alba")

        draft.select(transcriber)
        #expect(draft.voice == nil)
        draft.language = "de"
        draft.select(transcriber)
        #expect(draft.language == "de")
        draft.select(image())
        #expect(draft.language == nil)
    }

    @Test func anAttachmentTheNewModelCannotTakeIsDropped() throws {
        let files = try FileFixtures()
        var draft = GenerationDraft()
        draft.attachment = try files.file(named: "talk.mp3")

        draft.select(transcriber)
        #expect(draft.attachment != nil)

        draft.select(speech.named)
        #expect(draft.attachment == nil)
    }

    @Test func choosingNoModelKeepsTheAttachment() throws {
        var draft = GenerationDraft()
        draft.attachment = try FileFixtures().file(named: "talk.mp3")
        draft.select(nil)
        #expect(draft.recipeID == nil)
        #expect(draft.attachment != nil)
    }

    // MARK: - The request

    @Test func anImageRequestCarriesTheSettings() {
        var draft = GenerationDraft()
        draft.select(image())
        draft.prompt = "  A fox. \n"
        draft.negativePrompt = "blurry"
        draft.seed = 7

        let request = draft.request(for: image())

        #expect(request.prompt == "A fox.")
        #expect(request.image?.negativePrompt == "blurry")
        #expect(request.image?.width == 768)
        #expect(request.image?.seed == 7)
        #expect(request.image?.strength == nil)
        #expect(request.speech == nil)
    }

    @Test func theEditStrengthIsSentOnlyWithAnAttachment() {
        var draft = GenerationDraft()
        draft.editStrength = .strong
        #expect(draft.request(for: image()).image?.strength == nil)

        draft.attachment = URL(fileURLWithPath: "/a.png")
        let request = draft.request(for: image())
        #expect(request.image?.strength == 0.8)
        #expect(request.attachment == draft.attachment)
    }

    @Test func theRecipesSigmasAreSentOnlyAtItsOwnStepCount() {
        let recipe = image(steps: 2, sigmas: [1, 0.5, 0])
        var draft = GenerationDraft()
        draft.select(recipe)
        #expect(draft.request(for: recipe).image?.sigmas == [1, 0.5, 0])

        draft.steps = 4
        #expect(draft.request(for: recipe).image?.sigmas == nil)
    }

    @Test func aSpeechRequestCarriesTheVoiceAndNoImageSettings() {
        var draft = GenerationDraft()
        draft.select(speech.named)
        let request = draft.request(for: speech.named)
        #expect(request.speech == SpeechSettings(voice: "george"))
        #expect(request.image == nil)
    }

    @Test func aTranscriptRequestCarriesTheLanguageAndTheFile() {
        var draft = GenerationDraft()
        draft.language = "de"
        draft.attachment = URL(fileURLWithPath: "/talk.mp3")
        let request = draft.request(for: transcriber)
        #expect(request.language == "de")
        #expect(request.attachment == draft.attachment)
        #expect(request.image == nil && request.speech == nil)
    }

    // MARK: - Reusing a past image

    @Test func reusingAnImageRestoresItsSettingsAndItsSeed() {
        var draft = GenerationDraft()
        let settings = ImageSettings(
            negativePrompt: "blurry", width: 640, height: 480, steps: 12, cfg: 3.5, sampler: "heun", sigmas: nil, seed: 99, strength: nil
        )
        draft.apply(GenerationRequest(prompt: "A fox.", image: settings))

        #expect(draft.prompt == "A fox.")
        #expect(draft.negativePrompt == "blurry")
        #expect(draft.width == 640 && draft.height == 480 && draft.steps == 12)
        #expect(draft.sampler == "heun")
        #expect(!draft.randomSeed)
        #expect(draft.seed == 99)
    }

    @Test func reusingARequestWithoutImageSettingsOnlyTakesThePrompt() {
        var draft = GenerationDraft()
        draft.apply(GenerationRequest(prompt: "Hello."))
        #expect(draft.prompt == "Hello.")
        #expect(draft.randomSeed)
        #expect(draft.steps == 20)
    }

    // MARK: - Failures

    @Test func aLoneFileThatWillNotLoadIsExplained() {
        let message = GenerationFailure.message(for: EngineError.modelLoadFailed(detail: "x"), recipe: image())
        #expect(message.contains("\u{201C}Test\u{201D} is not a complete model"))
    }

    @Test func otherFailuresUseTheErrorsOwnWords() {
        let two = makeRecipe(components: [
            .init(role: .diffusionModel, repo: "o/r", file: "a.gguf"), .init(role: .vae, repo: "o/r", file: "b.safetensors"),
        ])
        let failed = EngineError.modelLoadFailed(detail: "x")
        #expect(GenerationFailure.message(for: failed, recipe: two) == failed.errorDescription)
        #expect(GenerationFailure.message(for: failed, recipe: speech.named) == failed.errorDescription)
        #expect(GenerationFailure.message(for: EngineError.busy, recipe: image()) == EngineError.busy.errorDescription)
    }
}
