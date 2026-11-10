import Foundation
import Testing
@testable import KilnCore

@Suite struct EngineMessageTests {
    @Test func decodesHelperEvents() {
        #expect(EngineMessage.decodeEvent(#"{"commit":"465adf3","type":"ready","version":"master-1"}"#)
            == .ready(version: "master-1", commit: "465adf3"))
        #expect(EngineMessage.decodeEvent(#"{"type":"loading"}"#) == .loading)
        #expect(EngineMessage.decodeEvent(#"{"completed":3,"detail":"","stage":"sampling","total":8,"type":"progress"}"#)
            == .progress(stage: "sampling", completed: 3, total: 8))
        #expect(EngineMessage.decodeEvent(#"{"channels":3,"height":64,"path":"/tmp/a.raw","type":"image","width":32}"#)
            == .image(path: "/tmp/a.raw", width: 32, height: 64, channels: 3))
        #expect(EngineMessage.decodeEvent(#"{"channels":3,"height":8,"path":"/tmp/a.preview","step":2,"type":"preview","width":8}"#)
            == .preview(path: "/tmp/a.preview", width: 8, height: 8, channels: 3))
        #expect(EngineMessage.decodeEvent(#"{"code":"load_failed","message":"nope","type":"error"}"#)
            == .error(code: "load_failed", message: "nope"))
        #expect(EngineMessage.decodeEvent(#"{"type":"cancelled"}"#) == .cancelled)
        #expect(EngineMessage.decodeEvent(#"{"type":"idle"}"#) == .idle)
    }

    @Test func ignoresLinesItDoesNotUnderstand() {
        #expect(EngineMessage.decodeEvent("ggml_metal_init: found device") == nil)
        #expect(EngineMessage.decodeEvent(#"{"type":"something_new"}"#) == nil)
        #expect(EngineMessage.decodeEvent(#"{"type":"image","path":"/tmp/a.raw"}"#) == nil)
    }

    @Test func generateCommandMapsRolesToPathsAndSettings() throws {
        let storage = ModelStorage(root: URL(fileURLWithPath: "/models"))
        let recipe = makeRecipe(
            components: [
                .init(role: .llm, repo: "a/enc", file: "enc.gguf"),
                .init(role: .diffusionModel, repo: "a/dn", file: "dn.gguf"),
                .init(role: .vae, repo: "c/vae", file: "vae/v.safetensors"),
            ],
            defaults: .init(steps: 2, cfg: 1, sampler: "euler", width: 64, height: 64, sigmas: [1, 0.5, 0], flashAttention: true)
        )
        let request = GenerationRequest(prompt: "a \"quoted\" cat", negativePrompt: "blurry", defaults: recipe.defaults, seed: 42)

        let data = try EngineMessage.generateCommand(recipe: recipe, storage: storage, request: request,
                                                       output: URL(fileURLWithPath: "/tmp/out.raw"), preview: URL(fileURLWithPath: "/tmp/out.preview"))

        #expect(data.last == 0x0A)
        #expect(data.dropLast().allSatisfy { $0 != 0x0A }, "the command must be a single line")
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let model = try #require(json["model"] as? [String: Any])
        let params = try #require(json["params"] as? [String: Any])
        #expect(json["type"] as? String == "generate")
        #expect(json["output"] as? String == "/tmp/out.raw")
        #expect(json["preview"] as? String == "/tmp/out.preview")
        #expect(model["llm"] as? String == "/models/a/enc/enc.gguf")
        #expect(model["diffusion_model"] as? String == "/models/a/dn/dn.gguf")
        #expect(model["vae"] as? String == "/models/c/vae/vae/v.safetensors")
        #expect(model["checkpoint"] == nil)
        #expect(model["flash_attention"] as? Bool == true)
        #expect(params["prompt"] as? String == "a \"quoted\" cat")
        #expect(params["negative_prompt"] as? String == "blurry")
        #expect(params["steps"] as? Int == 2)
        #expect(params["sigmas"] as? [Double] == [1, 0.5, 0])
        #expect(params["seed"] as? Int == 42)
    }

    @Test func recognisesOutOfMemoryLogs() {
        #expect(EngineMessage.indicatesOutOfMemory(["ggml_metal_buffer: failed to allocate Metal buffer of 99 bytes (out of memory)"]))
        #expect(EngineMessage.indicatesOutOfMemory(["error: failed to allocate buffer, size = 9000.00 MiB"]))
        #expect(EngineMessage.indicatesOutOfMemory(["command buffer failed: kIOGPUCommandBufferCallbackErrorOutOfMemory"]))
        #expect(!EngineMessage.indicatesOutOfMemory(["[info] loading model", "[error] unknown tensor"]))
    }

    @Test func mapsEngineStages() {
        #expect(EngineMessage.stage("sampling") == .sampling)
        #expect(EngineMessage.stage("conditioning") == .encodingPrompt)
        #expect(EngineMessage.stage("vae_decode") == .decoding)
        #expect(EngineMessage.stage("upscaling") == .other("upscaling"))
    }
}
