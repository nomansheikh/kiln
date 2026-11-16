import Foundation
import KilnCore
import Testing

/// The Speech screen: sending text, what happens to it, and the user's voices.
@MainActor
@Suite struct SpeechStoreTests {
    private let fixture: StoreFixture
    private let store: SpeechStore

    init() throws {
        fixture = try StoreFixture()
        store = fixture.speechStore()
        store.selectRecipe(StoreFixture.voice)
    }

    private func send(_ text: String) async throws {
        store.text = text
        store.generate()
        try await waitUntil("the clip has ended") { !store.isGenerating }
    }

    @Test func itStartsWithTheFirstInstalledVoiceModel() throws {
        let fresh = fixture.speechStore()
        #expect(fresh.recipes.map(\.id) == ["copier", "voice"])
        #expect(fresh.selectedRecipe?.id == "copier")
        #expect(!fresh.canGenerate)
    }

    @Test func selectingAModelPicksItsDefaultVoice() {
        #expect(store.selectedRecipe?.id == "voice")
        #expect(store.voice == "george")
    }

    @Test func sentTextBecomesAClipThatIsLoadedInThePlayer() async throws {
        fixture.engine.answer(.loadingModel, .finished(.audio(StoreFixture.sound)))
        store.text = " Hello there. "
        #expect(store.canGenerate)

        store.generate()
        #expect(store.text.isEmpty)
        #expect(store.activity == .loadingModel)
        #expect(!store.canGenerate)
        try await waitUntil("the clip arrived") { !store.isGenerating }

        let clip = try #require(fixture.audio.items.first)
        #expect(store.current?.id == clip.id)
        #expect(clip.record.request.prompt == "Hello there.")
        #expect(clip.record.request.speech?.voice == "george")
        #expect(fixture.engine.recipeIDs == ["voice"])
        #expect(store.errorMessage == nil)
        store.playback?.pause()
    }

    @Test func aFailureIsShownAndTheTextComesBack() async throws {
        fixture.engine.fail(with: EngineError.outOfMemory)
        try await send("Hello there.")

        #expect(store.text == "Hello there.")
        #expect(store.errorMessage == EngineError.outOfMemory.errorDescription)
        #expect(fixture.audio.items.isEmpty)
    }

    @Test func stoppingBringsTheTextBackWithoutAnError() async throws {
        fixture.engine.hold()
        store.text = "Hello there."
        store.generate()

        store.cancel()
        try await waitUntil("the clip was stopped") { !store.isGenerating }

        #expect(store.text == "Hello there.")
        #expect(store.errorMessage == nil)
    }

    @Test func textTypedMeanwhileIsNotOverwrittenWhenAClipFails() async throws {
        fixture.engine.hold()
        store.text = "First."
        store.generate()
        store.text = "Second."
        fixture.engine.fail(with: EngineError.outOfMemory)
        fixture.engine.release()
        try await waitUntil("the clip failed") { !store.isGenerating }
        #expect(store.text == "Second.")
    }

    @Test func nothingIsSentWhileAnotherScreenUsesTheEngine() {
        store.text = "Hello."
        store.isEngineBusyElsewhere = { true }
        #expect(!store.canGenerate)
        store.generate()
        #expect(fixture.engine.requests.isEmpty)
        #expect(store.text == "Hello.")
    }

    @Test func switchingTheModelKeepsTheTextAndPicksAVoiceItHas() {
        store.text = "Hello."
        store.selectRecipe(StoreFixture.copier)
        #expect(store.selectedRecipe?.id == "copier")
        #expect(store.voice == nil)
        #expect(store.text == "Hello.")
        #expect(store.voiceProblem == "This model speaks in a voice it copies. Add a voice first.")
        #expect(!store.canGenerate)
    }

    @Test func anAddedVoiceIsSelectedAndSentAsARecording() async throws {
        fixture.engine.answer(.finished(.audio(StoreFixture.sound)))
        store.selectRecipe(StoreFixture.copier)
        try store.addVoice(recording: try fixture.recording(), name: "Anna", transcript: "Hello there.")

        let anna = try #require(fixture.voices.voices.first)
        #expect(store.savedVoice == anna)
        #expect(store.canGenerate == false)
        try await send("Good morning.")

        let sent = try #require(fixture.engine.requests.last?.speech)
        #expect(sent.voice == nil)
        #expect(sent.reference?.name == "Anna")
        #expect(sent.reference?.transcript == "Hello there.")
        store.playback?.pause()
    }

    @Test func aVoiceAddedForASpeakerBecomesThatSpeakersVoice() throws {
        store.selectRecipe(StoreFixture.copier)
        store.text = "Anna: Hi.\nBen: Yo."
        store.addVoice(for: "Ben", designing: false)
        #expect(store.isAddingVoice)

        try store.addVoice(recording: try fixture.recording(), name: "Deep", transcript: "")
        store.isAddingVoice = false

        let deep = try #require(fixture.voices.voices.first)
        #expect(store.cast == ["ben": .saved(deep.id)])
        #expect(store.savedVoiceID == nil)
        #expect(store.pendingSpeaker == nil)
        #expect(store.speakerProblem == "Anna has no voice yet. Choose one under Speakers.")
    }

    @Test func aDesignedVoiceIsKeptWithItsDescription() async throws {
        fixture.engine.answer(.finished(.audio(StoreFixture.sound)))
        let sample = try await store.designSample(with: StoreFixture.copier, description: "elderly, low pitch", words: "Hello.")
        #expect(fixture.engine.requests.last?.speech?.instruction == "elderly, low pitch")
        #expect(store.preparingPreview == nil)

        store.selectRecipe(StoreFixture.copier)
        try store.saveDesigned(sample, name: "Grandpa", description: "elderly, low pitch", words: "Hello.")

        let voice = try #require(fixture.voices.voices.first)
        #expect(voice.design == "elderly, low pitch")
        #expect(voice.transcript == "Hello.")
        #expect(store.savedVoice == voice)
    }

    @Test func aVoicesNameAndWordsCanBeChanged() throws {
        try store.addVoice(recording: try fixture.recording(), name: "Anna", transcript: "")
        let anna = try #require(fixture.voices.voices.first)
        store.edit(anna)
        #expect(store.editedVoice == anna)

        try store.updateVoice(anna, name: " Anna B ", transcript: " Hello. ")
        #expect(fixture.voices.voices.first?.name == "Anna B")
        #expect(fixture.voices.voices.first?.transcript == "Hello.")
    }

    @Test func aClipsTextAndVoiceCanBeUsedAgain() async throws {
        fixture.engine.answer(.finished(.audio(StoreFixture.sound)))
        store.voice = "alba"
        try await send("Hello there.")
        store.playback?.pause()
        store.selectRecipe(StoreFixture.copier)

        store.reuse(try #require(fixture.audio.items.first))

        #expect(store.selectedRecipe?.id == "voice")
        #expect(store.text == "Hello there.")
        #expect(store.voice == "alba")
    }

    @Test func aRecordingsWordsAreWrittenDownByAnInstalledModel() async throws {
        fixture.engine.answer(.finished(.text(" Hello there. ")))
        #expect(store.transcriber?.id == "writer")
        let words = try await store.transcribe(try fixture.recording(), language: nil)
        #expect(words.trimmingCharacters(in: .whitespaces) == "Hello there.")
        #expect(fixture.engine.recipeIDs == ["writer"])
    }
}
