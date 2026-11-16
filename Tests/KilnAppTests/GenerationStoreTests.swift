import Foundation
import KilnCore
import Testing

/// The Generate screen: sending a prompt, what the thread shows, and saved chats.
@MainActor
@Suite struct GenerationStoreTests {
    private let fixture: StoreFixture
    private let store: GenerationStore

    init() throws {
        fixture = try StoreFixture()
        store = fixture.generationStore()
    }

    private func send(_ prompt: String) async throws {
        store.draft.prompt = prompt
        store.generate()
        try await waitUntil("the turn has ended") { !store.phase.isBusy }
    }

    @Test func itStartsWithAnImageModelAndItsSettings() {
        #expect(store.selectedRecipe?.id == "picture")
        #expect(store.draft.width == 768 && store.draft.steps == 8)
        #expect(!store.canGenerate)
    }

    @Test func aPromptMovesIntoTheThreadAndItsImageIntoTheGallery() async throws {
        fixture.engine.answer(.loadingModel, .finished(.image(StoreFixture.picture)))
        store.draft.prompt = " A fox. "
        #expect(store.canGenerate)

        store.generate()
        #expect(store.draft.prompt.isEmpty)
        #expect(store.turns.map(\.prompt) == ["A fox."])
        #expect(store.turns.first?.state == .running)
        #expect(!store.canGenerate)
        try await waitUntil("the image arrived") { !store.phase.isBusy }

        let image = try #require(store.turns.first?.image)
        #expect(fixture.gallery.items.map(\.id) == [image.id])
        #expect(store.latestImage == image)
        #expect(image.record.recipeID == "picture")
        #expect(fixture.engine.requests.first?.image?.width == 768)
        #expect(store.preview == nil)
    }

    @Test func eachPromptGetsANewSeedUnlessOneIsFixed() async throws {
        fixture.engine.answer(.finished(.image(StoreFixture.picture)))
        store.draft.randomSeed = false
        store.draft.seed = 7
        try await send("One.")
        store.draft.randomSeed = true
        try await send("Two.")
        try await send("Three.")

        let seeds = fixture.engine.requests.compactMap { $0.image?.seed }
        #expect(seeds.first == 7)
        #expect(seeds[1] != seeds[2])
    }

    @Test func theThreadIsSavedAsAChatNamedAfterItsFirstPrompt() async throws {
        fixture.engine.answer(.finished(.image(StoreFixture.picture)))
        try await send("A fox in the snow.")
        try await send("Now at night.")

        let chat = try #require(fixture.chats.chats.first)
        #expect(fixture.chats.chats.count == 1)
        #expect(chat.id == store.chatID)
        #expect(chat.title == "A fox in the snow.")
        #expect(chat.turns.map(\.prompt) == ["A fox in the snow.", "Now at night."])
    }

    @Test func aFailureIsShownInTheThreadAndTheModelCountsAsUnloaded() async throws {
        fixture.engine.fail(with: EngineError.outOfMemory)
        try await send("A fox.")

        #expect(store.turns.first?.state == .failed(EngineError.outOfMemory.errorDescription ?? ""))
        #expect(store.loadedRecipeID == nil)
        #expect(fixture.gallery.items.isEmpty)
        #expect(fixture.chats.chats.first?.turns.first?.outcome == .failed(message: EngineError.outOfMemory.errorDescription ?? ""))
    }

    @Test func anEngineThatEndsWithoutAResultIsAFailure() async throws {
        fixture.engine.answer(.loadingModel)
        try await send("A fox.")
        #expect(store.turns.first?.state == .failed("The engine finished without producing an image."))
    }

    @Test func stoppingARunningPromptMarksItStopped() async throws {
        fixture.engine.hold()
        store.draft.prompt = "A fox."
        store.generate()
        #expect(store.phase == .starting)

        store.cancel()
        try await waitUntil("the turn was stopped") { !store.phase.isBusy }
        #expect(store.turns.first?.state == .cancelled)
    }

    @Test func progressMarksTheModelAsLoaded() async throws {
        let progress = GenerationProgress(stage: .sampling, completed: 1, total: 8)
        fixture.engine.answer(.progress(progress), .preview(StoreFixture.picture), .finished(.image(StoreFixture.picture)))
        try await send("A fox.")
        #expect(store.loadedRecipeID == "picture")

        store.unloadModel()
        #expect(store.loadedRecipeID == nil)
        try await waitUntil("the engine was shut down") { fixture.engine.shutdownCount == 1 }
    }

    @Test func nothingIsSentWhileAnotherScreenUsesTheEngine() {
        store.draft.prompt = "A fox."
        store.isEngineBusyElsewhere = { true }
        #expect(!store.canGenerate)
        store.generate()
        #expect(store.turns.isEmpty)
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func aTranscriptAndAClipEachLandInTheThread() async throws {
        fixture.engine.answer(.finished(.text("Hello there.")))
        store.selectRecipe(StoreFixture.writer)
        try await send("Write this down.")
        #expect(store.turns.last?.state == .text("Hello there."))
        #expect(store.turns.last?.kind == .text)

        fixture.engine.answer(.finished(.audio(StoreFixture.sound)))
        store.selectRecipe(StoreFixture.voice)
        try await send("Hello.")
        #expect(fixture.audio.items.count == 1)
        guard case .audio(let clip) = store.turns.last?.state else {
            Issue.record("expected a clip in the thread")
            return
        }
        #expect(clip.id == fixture.audio.items[0].id)
        #expect(fixture.engine.requests.last?.speech?.voice == "george")
    }

    @Test func runningATurnAgainUsesItsPromptWithTheCurrentSettings() async throws {
        fixture.engine.answer(.finished(.image(StoreFixture.picture)))
        try await send("A fox.")
        store.draft.steps = 4

        store.regenerate(try #require(store.turns.first))
        try await waitUntil("the second image arrived") { !store.phase.isBusy }

        #expect(store.turns.map(\.prompt) == ["A fox.", "A fox."])
        #expect(fixture.engine.requests.last?.image?.steps == 4)
    }

    @Test func aNewChatEmptiesTheThreadAndASavedOneCanBeOpenedAgain() async throws {
        fixture.engine.answer(.finished(.image(StoreFixture.picture)))
        try await send("A fox.")
        let chat = try #require(fixture.chats.chats.first)
        let image = try #require(store.latestImage)

        store.startOver()
        #expect(store.turns.isEmpty && store.chatID == nil)

        store.open(chat)
        #expect(store.chatID == chat.id)
        #expect(store.turns.map(\.prompt) == ["A fox."])
        #expect(store.latestImage?.id == image.id)
    }

    @Test func reusingAnImageBringsBackItsModelAndSettings() async throws {
        fixture.engine.answer(.finished(.image(StoreFixture.picture)))
        store.draft.randomSeed = false
        store.draft.seed = 99
        try await send("A fox.")
        let image = try #require(store.latestImage)
        store.selectRecipe(StoreFixture.voice)
        store.draft.seed = 1

        store.reuseSettings(of: image)

        #expect(store.selectedRecipe?.id == "picture")
        #expect(store.draft.prompt == "A fox.")
        #expect(store.draft.seed == 99 && !store.draft.randomSeed)
    }

    @Test func aDeletedImageLeavesTheThreadAndItsChat() async throws {
        fixture.engine.answer(.finished(.image(StoreFixture.picture)))
        try await send("A fox.")
        try await send("A crow.")

        store.forget(try #require(store.turns.first?.image))

        #expect(store.turns.map(\.prompt) == ["A crow."])
        #expect(fixture.chats.chats.first?.turns.map(\.prompt) == ["A crow."])
    }
}
