import Foundation
import Testing
@testable import KilnCore

/// What the 3D screen sends, and where its objects are kept.
@Suite struct MeshDraftTests {
    private let picture = URL(fileURLWithPath: "/pictures/chair.png")
    private var shaper: ModelRecipe {
        ModelRecipe(
            id: "shaper", name: "Shaper", engine: TrellisCppEngine.engineID,
            components: [.init(role: .model, repo: "o/r", file: "ss_flow.gguf")], output: .mesh, accepts: [.image], defaults: nil
        )
    }

    @Test func itNeedsAModelThatMakesObjectsAndAPicture() {
        var draft = MeshDraft()
        #expect(!draft.canSend(with: shaper))
        #expect(draft.request == nil)

        draft.image = picture
        #expect(draft.canSend(with: shaper))
        #expect(!draft.canSend(with: nil))
        #expect(!draft.canSend(with: makeRecipe()))
    }

    @Test func theRequestCarriesThePictureAndEverySetting() throws {
        var draft = MeshDraft()
        draft.image = picture
        draft.detail = .fine
        draft.seed = 99
        draft.steps = 20
        draft.shapeGuidance = 5
        draft.cutout = .whiteBackground
        draft.textureSize = 2048

        let request = try #require(draft.request)
        #expect(request.attachment == picture)
        #expect(request.prompt.isEmpty)
        #expect(request.mesh == MeshSettings(
            detail: .fine, seed: 99, steps: 20, structureGuidance: 7.5, shapeGuidance: 5, cutout: .whiteBackground, textureSize: 2048
        ))
    }

    @Test func valuesOutsideWhatTheEngineTakesAreBroughtBack() {
        var draft = MeshDraft()
        draft.steps = 500
        draft.structureGuidance = 0
        draft.textureSize = 3000
        #expect(draft.settings.steps == 50)
        #expect(draft.settings.structureGuidance == 1)
        #expect(draft.settings.textureSize == nil)
    }

    @Test func advancedSettingsCanBePutBack() {
        var draft = MeshDraft()
        #expect(!draft.hasCustomSettings)
        draft.steps = 20
        draft.cutout = .model
        #expect(draft.hasCustomSettings)

        draft.detail = .fine
        draft.resetAdvanced()
        #expect(!draft.hasCustomSettings)
        // Detail is not an advanced setting.
        #expect(draft.detail == .fine)
    }

    @Test func aPastObjectBringsBackItsPictureSettingsAndSeed() {
        var draft = MeshDraft()
        let settings = MeshSettings(detail: .fine, seed: 5, steps: 8, cutout: .model, textureSize: 4096)
        draft.reuse(GenerationRequest(prompt: "", attachment: picture, mesh: settings))

        #expect(draft.image == picture)
        #expect(draft.settings == settings)
        #expect(!draft.randomSeed)
    }

    @Test func aPictureIsMadeIntoAnObjectAndADescriptionIsDrawnFirst() {
        let artist = makeRecipe()
        var draft = MeshDraft()
        #expect(draft.nextStep(objectRecipe: shaper, imageRecipe: artist) == nil)

        draft.prompt = "  a brass pocket watch "
        #expect(draft.nextStep(objectRecipe: shaper, imageRecipe: artist) == .picture)
        // Without a model that draws, or one that makes objects, words alone go nowhere.
        #expect(draft.nextStep(objectRecipe: shaper, imageRecipe: nil) == nil)
        #expect(draft.nextStep(objectRecipe: shaper, imageRecipe: shaper) == nil)
        #expect(draft.nextStep(objectRecipe: nil, imageRecipe: artist) == nil)

        // With a picture, the description is not used.
        draft.image = picture
        #expect(draft.nextStep(objectRecipe: shaper, imageRecipe: artist) == .object)
        #expect(draft.nextStep(objectRecipe: shaper, imageRecipe: nil) == .object)
    }

    @Test func thePictureIsAskedForSquareAndAsOneObjectOnAPlainBackground() throws {
        let artist = makeRecipe(defaults: .init(steps: 8, cfg: 1, sampler: "lcm", width: 1280, height: 768, sigmas: [1, 0]))
        var draft = MeshDraft()
        #expect(draft.pictureRequest(for: artist, seed: 3) == nil)

        draft.prompt = " a brass pocket watch\n"
        let request = try #require(draft.pictureRequest(for: artist, seed: 3))
        #expect(request.prompt == "a brass pocket watch, \(MeshDraft.pictureGuidance)")
        #expect(request.image?.width == 768 && request.image?.height == 768)
        #expect(request.image?.steps == 8 && request.image?.sampler == "lcm" && request.image?.seed == 3)
        #expect(request.image?.sigmas == [1, 0])
        #expect(request.attachment == nil && request.mesh == nil)
        // A model that draws no images cannot be asked for a picture.
        #expect(draft.pictureRequest(for: shaper, seed: 3) == nil)
    }

    @Test func aRecordSurvivesBeingSavedWithItsObject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-mesh-store-\(UUID().uuidString)")
        let store = MeshStore(directory: root)
        #expect(store.items().isEmpty)
        let request = GenerationRequest(prompt: "", attachment: picture, mesh: MeshSettings(detail: .fine, seed: 5))
        let older = GenerationRecord(createdAt: Date(timeIntervalSince1970: 1_000), recipeID: "shaper", recipeName: "Shaper", request: request)
        let newer = GenerationRecord(createdAt: Date(timeIntervalSince1970: 2_000), recipeID: "shaper", recipeName: "Shaper", request: request)

        let saved = try store.save(GeneratedMesh(glb: GLBFixture.square()), record: older)
        try store.save(GeneratedMesh(glb: GLBFixture.square()), record: newer)

        #expect(saved.url.pathExtension == "glb")
        #expect(store.items().map(\.id) == [newer.id, older.id])
        #expect(store.items().last?.record.request.mesh?.detail == .fine)
        #expect(try MeshFile(glb: Data(contentsOf: saved.url)).triangleCount == 2)

        try store.delete(saved, permanently: true)
        #expect(store.items().map(\.id) == [newer.id])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 2)
    }

    @Test func aModelThatMakesObjectsRunsOnAPictureAlone() {
        #expect(shaper.task == .objects)
        #expect(shaper.canRun(prompt: "", hasAttachment: true))
        #expect(!shaper.canRun(prompt: "a chair", hasAttachment: false))
        let image = makeRecipe(components: [.init(role: .checkpoint, repo: "o/r", file: "model.safetensors")])
        let catalog = ModelCatalog(recipes: [shaper, image], installedIDs: ["shaper", "test-model"])
        #expect(catalog.installedRecipes.count == 2)
        // The Generate screen leaves out models that have a screen of their own.
        #expect(catalog.chatRecipes.map(\.id) == ["test-model"])
    }
}
