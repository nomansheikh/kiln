import Foundation
import Testing
@testable import KilnCore

@Suite struct GenerationRequestTests {
    @Test func readsTheFlatLayoutOfImagesSavedBeforeKinds() throws {
        let json = """
        {"prompt": "a fox", "negativePrompt": "blurry", "width": 1024, "height": 768, "steps": 8, "cfg": 1,
         "sampler": "euler", "sigmas": [1, 0], "seed": 42, "sourceImage": "file:///tmp/a.png", "strength": 0.6}
        """

        let request = try JSONDecoder().decode(GenerationRequest.self, from: Data(json.utf8))

        #expect(request.prompt == "a fox")
        #expect(request.attachment == URL(string: "file:///tmp/a.png"))
        #expect(request.image == ImageSettings(
            negativePrompt: "blurry", width: 1024, height: 768, steps: 8, cfg: 1,
            sampler: "euler", sigmas: [1, 0], seed: 42, strength: 0.6
        ))
    }

    @Test func roundTripsInTheCurrentLayout() throws {
        let image = GenerationRequest(prompt: "a fox", defaults: .init(steps: 8, cfg: 1, sampler: "euler", width: 64, height: 64), seed: 7)
        let transcript = GenerationRequest(prompt: "", attachment: URL(fileURLWithPath: "/tmp/talk.m4a"))

        for request in [image, transcript] {
            let data = try JSONEncoder().encode(request)
            #expect(try JSONDecoder().decode(GenerationRequest.self, from: data) == request)
        }
        let keys = try JSONSerialization.jsonObject(with: JSONEncoder().encode(image)) as? [String: Any]
        #expect(keys.map { Set($0.keys) } == ["prompt", "image"])
    }

    @Test func aRequestWithoutImageSettingsHasNoImage() throws {
        let request = try JSONDecoder().decode(GenerationRequest.self, from: Data(#"{"prompt": "hello"}"#.utf8))

        #expect(request.image == nil)
        #expect(request.attachment == nil)
    }
}
