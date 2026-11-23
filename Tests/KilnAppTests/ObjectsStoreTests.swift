import Foundation
import KilnCore
import Testing

@MainActor
@Suite struct ObjectsStoreTests {
    private let fixture: StoreFixture
    private let store: ObjectsStore

    init() throws {
        let models = [StoreFixture.image, StoreFixture.shaper, StoreFixture.fineShaper]
        fixture = try StoreFixture(recipes: models, installed: models)
        store = fixture.objectsStore()
        store.selectRecipe(StoreFixture.shaper)
    }

    private func makeObject() async throws {
        fixture.engine.answer(.finished(.mesh(StoreFixture.object)))
        store.setPicture(try fixture.pictureFile())
        store.generate()
        try await waitUntil("the object was made") { !store.isGenerating }
    }

    @Test func aPictureBecomesAnObjectAndTheComposerEmpties() async throws {
        store.draft.detail = .fine
        try await makeObject()

        #expect(store.objects.items.count == 1)
        #expect(store.current?.id == store.objects.items.first?.id)
        #expect(store.draft.image == nil)
        #expect(store.errorMessage == nil)
        #expect(fixture.engine.recipeIDs == ["shaper"])
        #expect(fixture.engine.requests.last?.mesh?.detail == .fine)
        #expect(fixture.engine.requests.last?.attachment != nil)
    }

    @Test func nothingCanBeSentWithoutAPictureOrADescription() {
        #expect(store.nextStep == nil)
        #expect(!store.canGenerate)
        store.generate()
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func aDescriptionIsDrawnFirstAndHeldUpForApproval() async throws {
        fixture.engine.answer(.finished(.image(StoreFixture.picture)))
        store.draft.prompt = "A brass pocket watch"
        #expect(store.nextStep == .picture)
        store.generate()
        try await waitUntil("the picture was drawn") { !store.isGenerating }

        #expect(store.proposal != nil)
        #expect(store.objects.items.isEmpty)
        #expect(fixture.engine.recipeIDs == ["picture"])
        let sent = try #require(fixture.engine.requests.last)
        #expect(sent.prompt.hasPrefix("A brass pocket watch, "))
        #expect(sent.image?.width == sent.image?.height)
        // The description stays, so another picture can be drawn from it.
        #expect(store.draft.prompt == "A brass pocket watch")
    }

    @Test func approvingThePictureMakesTheObjectFromIt() async throws {
        fixture.engine.answer(.finished(.image(StoreFixture.picture)))
        store.draft.prompt = "A brass pocket watch"
        store.generate()
        try await waitUntil("the picture was drawn") { !store.isGenerating }

        fixture.engine.answer(.finished(.mesh(StoreFixture.object)))
        store.acceptProposal()
        try await waitUntil("the object was made") { !store.isGenerating && store.current != nil }

        #expect(fixture.engine.recipeIDs == ["picture", "shaper"])
        #expect(store.proposal == nil)
        #expect(store.objects.items.count == 1)
    }

    @Test func stoppingPutsThePictureBackWithoutAnError() async throws {
        fixture.engine.hold()
        store.setPicture(try fixture.pictureFile())
        let picture = store.draft.image
        store.generate()
        #expect(store.draft.image == nil)

        store.cancel()
        try await waitUntil("the object was stopped") { !store.isGenerating }

        #expect(store.draft.image == picture)
        #expect(store.errorMessage == nil)
        #expect(store.objects.items.isEmpty)
    }

    @Test func aFailurePutsThePictureBackAndSaysWhatHappened() async throws {
        fixture.engine.fail(with: EngineError.outOfMemory)
        store.setPicture(try fixture.pictureFile())
        let picture = store.draft.image
        store.generate()
        try await waitUntil("the object failed") { !store.isGenerating }

        #expect(store.draft.image == picture)
        #expect(store.errorMessage == EngineError.outOfMemory.errorDescription)
    }

    @Test func aPictureChosenMeanwhileIsNotReplacedWhenAnObjectFails() async throws {
        fixture.engine.hold()
        store.setPicture(try fixture.pictureFile())
        store.generate()
        store.setPicture(try fixture.pictureFile())
        let next = store.draft.image
        fixture.engine.fail(with: EngineError.outOfMemory)
        fixture.engine.release()
        try await waitUntil("the object failed") { !store.isGenerating }

        #expect(store.draft.image == next)
    }

    @Test func anObjectFinishedWhileAnotherIsLookedAtIsMarkedUnseen() async throws {
        try await makeObject()
        let first = try #require(store.current)

        fixture.engine.hold()
        store.setPicture(try fixture.pictureFile())
        store.generate()
        store.show(first)
        fixture.engine.release()
        try await waitUntil("the second object was made") { !store.isGenerating }

        #expect(store.current?.id == first.id)
        let second = try #require(store.objects.items.first { $0.id != first.id })
        #expect(store.unseenID == second.id)
        store.show(second)
        #expect(store.unseenID == nil)
    }

    @Test func nothingIsSentWhileAnotherScreenUsesTheEngine() throws {
        store.setPicture(try fixture.pictureFile())
        store.isEngineBusyElsewhere = { true }
        #expect(!store.canGenerate)
        store.generate()
        #expect(fixture.engine.requests.isEmpty)
        #expect(store.draft.image != nil)
    }

    @Test func aModelWithoutStandardDetailMovesToTheNextOneUp() {
        store.draft.detail = .standard
        store.selectRecipe(StoreFixture.fineShaper)
        #expect(store.selectedRecipe?.id == "fine-shaper")
        #expect(store.draft.detail == .fine)
    }

    @Test func reusingAnObjectPutsBackItsPictureAndSettingsForTheModelInUse() async throws {
        store.draft.steps = 20
        try await makeObject()
        let made = try #require(store.current)

        store.draft.resetAdvanced()
        store.selectRecipe(StoreFixture.shaper)
        store.reuse(made)

        #expect(store.draft.image == made.record.request.attachment)
        #expect(store.draft.steps == 20)
        #expect(!store.draft.randomSeed)
        #expect(store.draft.seed == made.record.request.mesh?.seed)
        #expect(store.selectedRecipe?.id == "shaper")
    }
}
