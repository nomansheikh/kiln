import Foundation
import Testing
@testable import KilnCore

@Suite struct EngineRouterTests {
    private let image = GeneratedImage(width: 1, height: 1, channels: 3, pixels: Data("abc".utf8))

    private func recipe(_ id: String, engine: String) -> ModelRecipe {
        var recipe = makeRecipe(id: id)
        recipe.engine = engine
        return recipe
    }

    private func run(_ router: EngineRouter, _ recipe: ModelRecipe) async throws -> [GenerationEvent] {
        var events: [GenerationEvent] = []
        for try await event in router.generate(recipe: recipe, request: GenerationRequest(prompt: "x")) {
            events.append(event)
        }
        return events
    }

    @Test func sendsTheRecipeToTheEngineItNames() async throws {
        let images = FakeEngine(events: [.loadingModel, .finished(.image(image))])
        let speech = FakeEngine()
        let router = EngineRouter(["sd.cpp": images, "speech": speech])

        let events = try await run(router, recipe("photo", engine: "sd.cpp"))

        #expect(events == [.loadingModel, .finished(.image(image))])
        #expect(images.generatedRecipeIDs == ["photo"])
        #expect(speech.generatedRecipeIDs.isEmpty)
    }

    @Test func rejectsAnEngineItDoesNotHave() async throws {
        let router = EngineRouter(["sd.cpp": FakeEngine()])

        await #expect(throws: EngineError.unsupportedEngine("other")) {
            try await run(router, recipe("photo", engine: "other"))
        }
    }

    @Test func shutsDownTheOtherEngineBeforeSwitching() async throws {
        let images = FakeEngine()
        let speech = FakeEngine()
        let router = EngineRouter(["sd.cpp": images, "speech": speech])

        _ = try await run(router, recipe("photo", engine: "sd.cpp"))
        _ = try await run(router, recipe("photo-2", engine: "sd.cpp"))
        #expect(images.shutdownCount == 0)

        _ = try await run(router, recipe("voice", engine: "speech"))
        #expect(images.shutdownCount == 1)
        #expect(speech.shutdownCount == 0)
    }

    @Test func shutdownStopsEveryEngine() async {
        let images = FakeEngine()
        let speech = FakeEngine()
        let router = EngineRouter(["sd.cpp": images, "speech": speech])

        await router.shutdown()

        #expect(images.shutdownCount == 1)
        #expect(speech.shutdownCount == 1)
    }
}
